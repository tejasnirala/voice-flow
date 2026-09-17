import AVFoundation
import Foundation
import VoiceFlowCore

/// `voiceflow-stt --transcribe-benchmark <audio-dir> --corpus <json> --out <jsonl> [--run name] [--voice label]`
///
/// Runs the helper's `WhisperEngine` with the user's settings (model, vocabulary prompt) and the app's `TranscriptGuard`
/// over benchmark WAVs, writing JSONL for `vf-bench score`. This is the same STT code path as live dictation.
/// Developer tool: transcripts are written only to the explicitly given output file.
enum BenchmarkMode {
    static func run(arguments args: [String]) -> Int32 {
        func value(_ flag: String) -> String? { args.firstIndex(of: flag).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } }
        guard let audioDir = value("--transcribe-benchmark"), let corpusPath = value("--corpus"), let outPath = value("--out") else {
            FileHandle.standardError.write(Data("usage: voiceflow-stt --transcribe-benchmark <dir> --corpus <json> --out <jsonl>\n".utf8))
            return 2
        }
        let settings = SettingsStore(directory: SettingsStore.applicationSupportDirectory()).load().settings
        let run = value("--run") ?? "in-app-\(settings.sttModel.id)\(settings.useVocabularyPrompt ? "+vocab" : "")"
        let voice = value("--voice") ?? URL(fileURLWithPath: audioDir).lastPathComponent
        do {
            let corpus = try BenchmarkCorpus.load(from: URL(fileURLWithPath: corpusPath))
            let model = settings.sttModel
            let (status, _) = STTModelManager.verify(model)
            guard status == .installed else {
                throw NSError(domain: "BenchmarkMode", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "model \(model.id): \(status)"])
            }
            let engine = WhisperEngine(modelPath: STTModelManager.url(for: model).path, modelFileName: model.fileName,
                                       language: model.language,
                                       prompt: settings.useVocabularyPrompt ? DeveloperVocabulary.prompt() : nil)
            defer { engine.unload() }
            let loadSeconds = try engine.prepare()
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
                let analysis = RecordingGate.analyze(samples, sampleRate: STTAudio.sampleRate)
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
                                          "model_mb": Double(model.sizeBytes) / 1_048_576, "encoder": engine.encoderName]
            try out.write(contentsOf: JSONSerialization.data(withJSONObject: summary, options: [.sortedKeys]) + Data("\n".utf8))
            FileHandle.standardError.write(Data("transcribed \(count) clips (\(engine.encoderName)) → \(outPath)\n".utf8))
            return 0
        } catch {
            FileHandle.standardError.write(Data("benchmark failed: \(error.localizedDescription)\n".utf8))
            return 1
        }
    }

    private static func readSamples(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard file.processingFormat.sampleRate == STTAudio.sampleRate, file.processingFormat.channelCount == 1,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw NSError(domain: "BenchmarkMode", code: 2, userInfo: [NSLocalizedDescriptionKey: "\(url.lastPathComponent) must be 16 kHz mono"])
        }
        try file.read(into: buffer)
        return Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
    }
}
