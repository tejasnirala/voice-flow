import Foundation
import VoiceFlowCore
import whisper

/// whisper.cpp (encoder on Core ML when available, otherwise Metal). Runs only inside the `voiceflow-stt` helper process.
/// One `whisper_context` guarded by a lock; `unload()` must run before exit, or ggml's Metal teardown asserts.
///
/// Inference settings match the benchmark harness that selected the model (scripts/bench/stt_engines.swift):
/// greedy decoding, 4 threads, no timestamps, Metal + flash attention, fixed language, optional vocabulary prompt.
final class WhisperEngine: @unchecked Sendable {
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

    let modelPath: String
    let modelFileName: String
    let language: String
    let prompt: String?

    private let lock = NSLock()
    private var context: OpaquePointer?

    private static let silenceLogs: Void = {
        // whisper.cpp logs verbosely to stderr; VoiceFlow logs its own metrics instead.
        // VOICEFLOW_WHISPER_LOG=1 (developer experiments) keeps whisper.cpp's logs.
        guard ProcessInfo.processInfo.environment["VOICEFLOW_WHISPER_LOG"] != "1" else { return }
        whisper_log_set({ _, _, _ in }, nil)
    }()

    init(modelPath: String, modelFileName: String, language: String, prompt: String?) {
        self.modelPath = modelPath
        self.modelFileName = modelFileName
        self.language = language
        self.prompt = prompt
        _ = Self.silenceLogs
    }

    convenience init(_ request: SpeechHelperMessage.Prepare) {
        self.init(modelPath: request.modelPath, modelFileName: request.modelFileName, language: request.language, prompt: request.prompt)
    }

    /// Whether whisper.cpp will find a Core ML encoder next to the model.
    var encoderName: String {
        let dir = URL(fileURLWithPath: modelPath).deletingLastPathComponent()
            .appendingPathComponent(STTModel.coreMLEncoderDirectoryName(forModelFileName: modelFileName))
        return FileManager.default.fileExists(atPath: dir.resolvingSymlinksInPath().path) ? "Core ML (Neural Engine)" : "Metal"
    }

    var isLoaded: Bool { lock.withLock { context != nil } }

    /// Loads the model if needed; returns the seconds spent loading.
    @discardableResult
    func prepare() throws -> Double {
        try lock.withLock { try loadLocked() }
    }

    /// Loads the model if needed. Returns the seconds spent loading (0 if it was already loaded).
    private func loadLocked() throws -> Double {
        guard context == nil else { return 0 }
        let start = DispatchTime.now().uptimeNanoseconds
        var params = whisper_context_default_params()
        params.use_gpu = true
        params.flash_attn = true
        guard let ctx = whisper_init_from_file_with_params(modelPath, params) else {
            throw EngineError.loadFailed(modelFileName)
        }
        context = ctx
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9
    }

    func transcribe(_ samples: [Float]) throws -> TranscriptionResult {
        try transcribe(samples, language: language, prompt: prompt)
    }

    /// Probability per candidate language (Whisper codes) from the first ≤ 30 s of speech (long pauses removed).
    func detectLanguage(_ samples: [Float], candidates: [String]) throws -> (probabilities: [String: Double], seconds: Double) {
        lock.lock()
        defer { lock.unlock() }
        _ = try loadLocked()
        guard let ctx = context else { throw EngineError.loadFailed(modelFileName) }
        let start = DispatchTime.now().uptimeNanoseconds
        let chunks = SpeechSegmenter.chunks(for: samples, sampleRate: STTAudio.sampleRate)
        let audio = chunks.first.map { SpeechSegmenter.audio(for: $0, in: samples) } ?? samples
        guard audio.withUnsafeBufferPointer({ whisper_pcm_to_mel(ctx, $0.baseAddress, Int32($0.count), 4) }) == 0 else {
            throw EngineError.inferenceFailed(-1)
        }
        var all = [Float](repeating: 0, count: Int(whisper_lang_max_id()) + 1)
        let best = all.withUnsafeMutableBufferPointer { whisper_lang_auto_detect(ctx, 0, 4, $0.baseAddress) }
        guard best >= 0 else { throw EngineError.inferenceFailed(best) }
        var probabilities: [String: Double] = [:]
        for code in candidates {
            let id = code.withCString { whisper_lang_id($0) }
            if id >= 0 { probabilities[code] = Double(all[Int(id)]) }
        }
        return (probabilities, Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9)
    }

    func transcribe(_ samples: [Float], language requestedLanguage: String, prompt requestedPrompt: String?) throws -> TranscriptionResult {
        let requested = DispatchTime.now().uptimeNanoseconds
        lock.lock()
        defer { lock.unlock() }
        let waited = Double(DispatchTime.now().uptimeNanoseconds - requested) / 1e9

        let cold = context == nil
        let loadSeconds = try loadLocked()
        guard let ctx = context else { throw EngineError.loadFailed(modelFileName) }

        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.n_threads = 4
        params.print_progress = false
        params.print_realtime = false
        params.print_timestamps = false
        params.print_special = false
        params.no_timestamps = true
        params.no_context = true

        let language = strdup(requestedLanguage)
        let promptCString = requestedPrompt.map { strdup($0) }
        defer {
            free(language)
            promptCString.map { free($0) }
        }
        params.language = UnsafePointer(language)
        if let promptCString { params.initial_prompt = UnsafePointer(promptCString) }

        // Long recordings: drop long pauses and transcribe ≤ 29 s chunks independently (SpeechSegmenter).
        // The encoder always uses Whisper's full 30 s window: fitting it to the audio (audio_ctx) was 2–3× faster but
        // failed the accuracy gate, returning empty transcripts for some clips (PERFORMANCE.md §3.5).
        let chunks = SpeechSegmenter.chunks(for: samples, sampleRate: STTAudio.sampleRate)
        var texts: [String] = []
        var transcribedSamples = 0
        let start = DispatchTime.now().uptimeNanoseconds
        for chunk in chunks {
            let audio = chunk == [0..<samples.count] ? samples : SpeechSegmenter.audio(for: chunk, in: samples)
            transcribedSamples += audio.count
            let status = audio.withUnsafeBufferPointer { whisper_full(ctx, params, $0.baseAddress, Int32($0.count)) }
            guard status == 0 else { throw EngineError.inferenceFailed(status) }
            let text = (0..<whisper_full_n_segments(ctx))
                .map { String(cString: whisper_full_get_segment_text(ctx, $0)) }
                .joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { texts.append(text) }
        }
        let seconds = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9

        var result = TranscriptionResult(text: texts.joined(separator: " "),
                                         audioSeconds: Double(samples.count) / STTAudio.sampleRate,
                                         transcribeSeconds: seconds, coldStart: cold, loadSeconds: loadSeconds,
                                         waitedForModelSeconds: waited)
        result.chunkCount = chunks.count
        result.transcribedAudioSeconds = Double(transcribedSamples) / STTAudio.sampleRate
        return result
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
