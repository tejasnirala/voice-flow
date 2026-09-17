import Foundation
import VoiceFlowCore
import whisper

/// whisper.cpp on Metal. One `whisper_context` guarded by a lock: calls are serialized, and `unload()` waits
/// for an in-flight transcription (required before exit, or ggml's Metal teardown asserts).
///
/// Inference settings match the benchmark harness that selected the model (scripts/bench/stt_engines.swift):
/// greedy decoding, 4 threads, no timestamps, Metal + flash attention, fixed language, optional vocabulary prompt.
final class WhisperEngine: SpeechEngine, @unchecked Sendable {
    enum EngineError: LocalizedError {
        case loadFailed(String)
        case inferenceFailed(Int32)

        var errorDescription: String? {
            switch self {
            case .loadFailed(let name): "The speech model couldn't be loaded (\(name))"
            case .inferenceFailed(let code): "Transcription failed (whisper error \(code))"
            }
        }
    }

    let model: STTModel
    let modelURL: URL
    let prompt: String?

    private let lock = NSLock()
    private var context: OpaquePointer?

    private static let silenceLogs: Void = {
        // whisper.cpp logs verbosely to stderr; VoiceFlow logs its own metrics instead.
        whisper_log_set({ _, _, _ in }, nil)
    }()

    init(model: STTModel, modelURL: URL, prompt: String?) {
        self.model = model
        self.modelURL = modelURL
        self.prompt = prompt
        _ = Self.silenceLogs
    }

    var isLoaded: Bool { lock.withLock { context != nil } }

    func prepare() throws {
        try lock.withLock { _ = try loadLocked() }
    }

    /// Loads the model if needed. Returns the seconds spent loading (0 if it was already loaded).
    private func loadLocked() throws -> Double {
        guard context == nil else { return 0 }
        let start = DispatchTime.now().uptimeNanoseconds
        var params = whisper_context_default_params()
        params.use_gpu = true
        params.flash_attn = true
        guard let ctx = whisper_init_from_file_with_params(modelURL.path, params) else {
            throw EngineError.loadFailed(model.fileName)
        }
        context = ctx
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9
    }

    func transcribe(_ samples: [Float]) throws -> TranscriptionResult {
        let requested = DispatchTime.now().uptimeNanoseconds
        lock.lock()
        defer { lock.unlock() }
        let waited = Double(DispatchTime.now().uptimeNanoseconds - requested) / 1e9

        let cold = context == nil
        let loadSeconds = try loadLocked()
        guard let ctx = context else { throw EngineError.loadFailed(model.fileName) }

        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.n_threads = 4
        params.print_progress = false
        params.print_realtime = false
        params.print_timestamps = false
        params.print_special = false
        params.no_timestamps = true
        params.no_context = true

        let language = strdup(model.language)
        let promptCString = prompt.map { strdup($0) }
        defer {
            free(language)
            promptCString.map { free($0) }
        }
        params.language = UnsafePointer(language)
        if let promptCString { params.initial_prompt = UnsafePointer(promptCString) }

        let start = DispatchTime.now().uptimeNanoseconds
        let status = samples.withUnsafeBufferPointer { whisper_full(ctx, params, $0.baseAddress, Int32($0.count)) }
        let seconds = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9
        guard status == 0 else { throw EngineError.inferenceFailed(status) }

        let text = (0..<whisper_full_n_segments(ctx))
            .map { String(cString: whisper_full_get_segment_text(ctx, $0)) }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return TranscriptionResult(text: text, audioSeconds: Double(samples.count) / AudioRecorder.sampleRate,
                                   transcribeSeconds: seconds, coldStart: cold, loadSeconds: loadSeconds,
                                   waitedForModelSeconds: waited)
    }

    func unload() {
        lock.withLock {
            guard let ctx = context else { return }
            whisper_free(ctx)
            context = nil
        }
    }

    deinit {
        if let context { whisper_free(context) }
    }
}
