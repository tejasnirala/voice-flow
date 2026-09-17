import Foundation
import os
import VoiceFlowCore

/// `SpeechEngine` backed by the `voiceflow-stt` helper process (see `SpeechHelperProtocol`).
///
/// The helper can hold several models (Auto language: a detector and a transcriber); `unload()` makes it exit, which
/// returns all of its memory. Calls block the calling (background) thread and are serialized by a lock. If the helper dies, the current
/// request fails with a readable error; the next request starts a fresh helper.
final class HelperSpeechEngine: @unchecked Sendable {
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

    /// Most recent successful load (for logging): helper launch + model load, seconds, and the encoder in use.
    private(set) var lastLoad: (launchSeconds: Double, loadSeconds: Double, encoder: String)?

    private let lock = NSLock()
    private var process: Process?
    private var toHelper: FileHandle?
    private var fromHelper: FileHandle?
    /// Model files loaded in the running helper (several at once for Auto language: detector + transcriber).
    private var preparedPaths: Set<String> = []
    /// Signalled by the process termination handler (installed at launch, so an early exit can't be missed).
    private var exited: DispatchSemaphore?

    var isRunning: Bool { lock.withLock { process?.isRunning == true } }

    func isLoaded(_ url: URL) -> Bool { lock.withLock { process?.isRunning == true && preparedPaths.contains(url.path) } }

    /// Starts the helper if needed and loads `model` (keeps other loaded models). Returns seconds spent.
    @discardableResult
    func prepare(_ model: STTModel, url: URL) throws -> Double {
        try lock.withLock { try prepareLocked(model, url: url) }
    }

    func transcribe(_ samples: [Float], model: STTModel, url: URL, language: String, prompt: String?) throws -> TranscriptionResult {
        let requested = DispatchTime.now().uptimeNanoseconds
        lock.lock()
        defer { lock.unlock() }
        let waited = Double(DispatchTime.now().uptimeNanoseconds - requested) / 1e9
        let cold = !(process?.isRunning == true && preparedPaths.contains(url.path))
        let loadSeconds = cold ? try prepareLocked(model, url: url) : 0

        let options = SpeechHelperMessage.Transcribe(modelPath: url.path, modelFileName: model.fileName, language: language, prompt: prompt)
        switch try requestLocked(.transcribe(options, samples)) {
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

    /// Probability per candidate language (Whisper codes) and the seconds detection took.
    func detectLanguage(_ samples: [Float], model: STTModel, url: URL, candidates: [String]) throws -> (probabilities: [String: Double], seconds: Double) {
        lock.lock()
        defer { lock.unlock() }
        if !(process?.isRunning == true && preparedPaths.contains(url.path)) { try prepareLocked(model, url: url) }
        let options = SpeechHelperMessage.Detect(modelPath: url.path, modelFileName: model.fileName, candidates: candidates)
        switch try requestLocked(.detectLanguage(options, samples)) {
        case .detection(let d): return (d.probabilities, d.seconds)
        case .failure(let message): throw HelperError.helper(message)
        default: throw HelperError.protocolViolation
        }
    }

    func unload() {
        lock.withLock { stopLocked(graceful: true) }
    }

    // MARK: - Locked helpers

    @discardableResult
    private func prepareLocked(_ model: STTModel, url: URL) throws -> Double {
        if process?.isRunning == true, preparedPaths.contains(url.path) { return 0 }
        let start = DispatchTime.now().uptimeNanoseconds
        try launchLocked()
        let launched = DispatchTime.now().uptimeNanoseconds
        let request = SpeechHelperMessage.Prepare(modelPath: url.path, modelFileName: model.fileName, language: model.language, prompt: nil)
        switch try requestLocked(.prepare(request)) {
        case .ready(let ready):
            preparedPaths.insert(url.path)
            let total = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9
            lastLoad = (Double(launched - start) / 1e9, ready.loadSeconds, ready.encoder)
            return total
        case .failure(let message):
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
        preparedPaths = []
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
        preparedPaths = []
    }

    /// The helper ships next to the app executable (Contents/MacOS/voiceflow-stt, or .build/<config>/ when unbundled).
    static var helperURL: URL? {
        if let url = Bundle.main.url(forAuxiliaryExecutable: "voiceflow-stt") { return url }
        let sibling = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
            .deletingLastPathComponent().appendingPathComponent("voiceflow-stt")
        return FileManager.default.isExecutableFile(atPath: sibling.path) ? sibling : nil
    }
}
