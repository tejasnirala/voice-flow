import Foundation
import os
import VoiceFlowCore

/// `SpeechEngine` backed by the `voiceflow-stt` helper process (see `SpeechHelperProtocol`).
///
/// "Loaded" means the helper is running with the model loaded; `unload()` makes it exit, which returns all of its
/// memory. Calls block the calling (background) thread and are serialized by a lock. If the helper dies, the current
/// request fails with a readable error; the next request starts a fresh helper.
final class HelperSpeechEngine: SpeechEngine, @unchecked Sendable {
    enum HelperError: LocalizedError {
        case notFound
        case launchFailed(String)
        case exited
        case helper(String)
        case protocolViolation

        var errorDescription: String? {
            switch self {
            case .notFound: "The speech helper (voiceflow-stt) is missing from the app bundle"
            case .launchFailed(let reason): "The speech helper couldn't start (\(reason))"
            case .exited: "The speech helper stopped unexpectedly"
            case .helper(let message): message
            case .protocolViolation: "The speech helper sent an unexpected reply"
            }
        }
    }

    let model: STTModel
    let modelURL: URL
    let prompt: String?

    /// Most recent successful load (for logging): helper launch + model load, seconds, and the encoder in use.
    private(set) var lastLoad: (launchSeconds: Double, loadSeconds: Double, encoder: String)?

    private let lock = NSLock()
    private var process: Process?
    private var toHelper: FileHandle?
    private var fromHelper: FileHandle?
    private var prepared = false
    /// Signalled by the process termination handler (installed at launch, so an early exit can't be missed).
    private var exited: DispatchSemaphore?

    init(model: STTModel, modelURL: URL, prompt: String?) {
        self.model = model
        self.modelURL = modelURL
        self.prompt = prompt
    }

    var isLoaded: Bool { lock.withLock { prepared && process?.isRunning == true } }

    func prepare() throws {
        _ = try lock.withLock { try prepareLocked() }
    }

    func transcribe(_ samples: [Float]) throws -> TranscriptionResult {
        let requested = DispatchTime.now().uptimeNanoseconds
        lock.lock()
        defer { lock.unlock() }
        let waited = Double(DispatchTime.now().uptimeNanoseconds - requested) / 1e9
        let cold = !(prepared && process?.isRunning == true)
        let loadSeconds = cold ? try prepareLocked() : 0

        switch try requestLocked(.transcribe(samples)) {
        case .transcription(let t):
            var result = TranscriptionResult(text: t.text, audioSeconds: t.audioSeconds, transcribeSeconds: t.transcribeSeconds,
                                             coldStart: cold, loadSeconds: loadSeconds, waitedForModelSeconds: waited)
            result.chunkCount = t.chunkCount
            result.transcribedAudioSeconds = t.transcribedAudioSeconds
            return result
        case .failure(let message): throw HelperError.helper(message)
        default: throw HelperError.protocolViolation
        }
    }

    func unload() {
        lock.withLock { stopLocked(graceful: true) }
    }

    // MARK: - Locked helpers

    /// Starts the helper if needed and loads the model. Returns seconds spent (launch + load).
    @discardableResult
    private func prepareLocked() throws -> Double {
        if prepared, process?.isRunning == true { return 0 }
        let start = DispatchTime.now().uptimeNanoseconds
        try launchLocked()
        let launched = DispatchTime.now().uptimeNanoseconds
        let request = SpeechHelperMessage.Prepare(modelPath: modelURL.path, modelFileName: model.fileName,
                                                  language: model.language, prompt: prompt)
        switch try requestLocked(.prepare(request)) {
        case .ready(let ready):
            prepared = true
            let total = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9
            lastLoad = (Double(launched - start) / 1e9, ready.loadSeconds, ready.encoder)
            return total
        case .failure(let message):
            stopLocked(graceful: true)
            throw HelperError.helper(message)
        default:
            stopLocked(graceful: false)
            throw HelperError.protocolViolation
        }
    }

    private func launchLocked() throws {
        if process?.isRunning == true { return }
        stopLocked(graceful: false)
        guard let url = Self.helperURL else { throw HelperError.notFound }
        let process = Process()
        process.executableURL = url
        let stdin = Pipe(), stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do {
            try process.run()
        } catch {
            throw HelperError.launchFailed(error.localizedDescription)
        }
        self.process = process
        self.exited = exited
        toHelper = stdin.fileHandleForWriting
        fromHelper = stdout.fileHandleForReading
        prepared = false
    }

    private func requestLocked(_ message: SpeechHelperMessage) throws -> SpeechHelperMessage {
        guard let toHelper, let fromHelper else { throw HelperError.exited }
        do {
            try toHelper.write(contentsOf: SpeechHelperWire.encode(message))
            return try SpeechHelperWire.decode(read: { try fromHelper.readExactly($0) })
        } catch {
            // Broken pipe or end of stream: the helper crashed or was killed.
            stopLocked(graceful: false)
            throw HelperError.exited
        }
    }

    private func stopLocked(graceful: Bool) {
        guard let process else { return }
        if graceful, process.isRunning, let toHelper {
            try? toHelper.write(contentsOf: SpeechHelperWire.encode(.shutdown))
        }
        try? toHelper?.close()
        // The helper frees whisper.cpp and exits on shutdown or when its stdin closes; don't wait forever.
        if process.isRunning, exited?.wait(timeout: .now() + 3) == .timedOut {
            process.terminate()
        }
        exited = nil
        try? fromHelper?.close()
        self.process = nil
        toHelper = nil
        fromHelper = nil
        prepared = false
    }

    /// The helper ships next to the app executable (Contents/MacOS/voiceflow-stt, or .build/<config>/ when unbundled).
    static var helperURL: URL? {
        if let url = Bundle.main.url(forAuxiliaryExecutable: "voiceflow-stt") { return url }
        let sibling = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
            .deletingLastPathComponent().appendingPathComponent("voiceflow-stt")
        return FileManager.default.isExecutableFile(atPath: sibling.path) ? sibling : nil
    }
}
