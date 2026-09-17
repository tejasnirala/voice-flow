import AppKit
import AVFoundation
import VoiceFlowCore

/// `VoiceFlow --transcribe-benchmark <audio-dir> --corpus <json> --out <jsonl> [--run name] [--voice label]`
///
/// Runs the app's own `WhisperEngine` (same model, prompt and guard as live dictation) over benchmark WAVs and
/// writes JSONL for `vf-bench score`. It proves the in-app STT path matches the benchmark that selected the
/// model. Developer tool: it writes transcripts only to the explicitly given output file.
@MainActor
enum BenchmarkMode {
    static func runIfRequested(settings: Settings) -> Bool {
        let args = ProcessInfo.processInfo.arguments
        func value(_ flag: String) -> String? { args.firstIndex(of: flag).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } }
        guard let audioDir = value("--transcribe-benchmark"), let corpusPath = value("--corpus"), let outPath = value("--out") else {
            return false
        }
        let run = value("--run") ?? "in-app-\(settings.sttModel.id)\(settings.useVocabularyPrompt ? "+vocab" : "")"
        let voice = value("--voice") ?? URL(fileURLWithPath: audioDir).lastPathComponent

        Task.detached(priority: .userInitiated) {
            let code = await transcribe(audioDir: audioDir, corpusPath: corpusPath, outPath: outPath, run: run,
                                        voice: voice, settings: settings)
            await MainActor.run { exit(code) }
        }
        return true
    }

    private static func transcribe(audioDir: String, corpusPath: String, outPath: String, run: String, voice: String,
                                   settings: Settings) async -> Int32 {
        do {
            let corpus = try BenchmarkCorpus.load(from: URL(fileURLWithPath: corpusPath))
            let model = settings.sttModel
            let (status, _) = STTModelManager.verify(model)
            guard status == .installed else { throw DictationCoordinator.ModelUnavailable(status: status, model: model) }
            let engine = WhisperEngine(model: model, modelURL: STTModelManager.url(for: model),
                                       prompt: settings.useVocabularyPrompt ? STTModelManager.vocabularyPrompt() : nil)
            defer { engine.unload() }

            let loadStart = DispatchTime.now().uptimeNanoseconds
            try engine.prepare()
            let loadSeconds = Double(DispatchTime.now().uptimeNanoseconds - loadStart) / 1e9
            let afterLoad = ResourceUsage.footprintMB

            FileManager.default.createFile(atPath: outPath, contents: nil)
            let out = try FileHandle(forWritingTo: URL(fileURLWithPath: outPath))
            defer { try? out.close() }
            var firstRun: Double?
            var count = 0
            for entry in corpus.entries {
                let url = URL(fileURLWithPath: audioDir).appendingPathComponent("\(entry.id).wav")
                guard FileManager.default.fileExists(atPath: url.path) else { continue }
                let samples = try readSamples(url)
                let analysis = RecordingGate.analyze(samples, sampleRate: AudioRecorder.sampleRate)
                var result = try engine.transcribe(samples)
                if firstRun == nil { firstRun = result.transcribeSeconds; result = try engine.transcribe(samples) }
                let cleaned = TranscriptGuard.clean(result.text, speechSeconds: analysis.speechSeconds)
                let line: [String: Any] = ["type": "clip", "run": run, "id": entry.id, "voice": voice,
                                           "audio_s": result.audioSeconds, "latency_s": result.transcribeSeconds,
                                           "text": cleaned.text, "guard": cleaned.flags.map(\.rawValue).sorted(),
                                           "chunks": result.chunkCount, "transcribed_audio_s": result.transcribedAudioSeconds]
                try out.write(contentsOf: JSONSerialization.data(withJSONObject: line, options: [.sortedKeys]) + Data("\n".utf8))
                count += 1
            }
            let summary: [String: Any] = ["type": "run", "run": run, "load_s": loadSeconds, "first_run_s": firstRun ?? 0,
                                          "footprint_after_load_mb": afterLoad, "peak_footprint_mb": ResourceUsage.peakFootprintMB,
                                          "model_mb": Double(model.sizeBytes) / 1_048_576]
            try out.write(contentsOf: JSONSerialization.data(withJSONObject: summary, options: [.sortedKeys]) + Data("\n".utf8))
            FileHandle.standardError.write(Data("transcribed \(count) clips → \(outPath)\n".utf8))
            return 0
        } catch {
            FileHandle.standardError.write(Data("benchmark failed: \(error.localizedDescription)\n".utf8))
            return 1
        }
    }

    private static func readSamples(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard file.processingFormat.sampleRate == AudioRecorder.sampleRate, file.processingFormat.channelCount == 1,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw NSError(domain: "BenchmarkMode", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(url.lastPathComponent) must be 16 kHz mono"])
        }
        try file.read(into: buffer)
        return Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
    }
}
