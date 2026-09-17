// STT benchmark engine harness (developer tool, not part of the app).
// Transcribes every corpus clip found in --audio-dir with one engine configuration and writes
// JSONL for `vf-bench score`. Compiled by scripts/bench/stt.sh against Vendor/whisper.xcframework.
//
//   stt_engines --engine whisper|parakeet|apple --model <path|locale> [--backend metal|cpu]
//               [--prompt-file <txt>] --corpus <json> --audio-dir <dir> --voice <label>
//               --run <name> --out <file.jsonl>
import AVFoundation
import Darwin
import Foundation
import Speech
import whisper

// MARK: - Arguments

var opts: [String: String] = [:]
do {
    var it = CommandLine.arguments.dropFirst().makeIterator()
    while let k = it.next() { if k.hasPrefix("--") { opts[String(k.dropFirst(2))] = it.next() ?? "" } }
}
func opt(_ k: String) -> String { guard let v = opts[k] else { fatalError("missing --\(k)") }; return v }
let engineName = opt("engine"), modelArg = opt("model"), runName = opt("run"), voice = opt("voice")
let useGPU = (opts["backend"] ?? "metal") == "metal"
/// Whisper language: a code ("en", "de", "hi") or "auto3" = detect among English, German and Hindi, then transcribe in it.
let language = opts["language"] ?? "en"
/// Set by an engine that detected the language for the last clip: ["detected": code, "p_en": …, "p_de": …, "p_hi": …].
nonisolated(unsafe) var lastDetection: [String: Any]?
let prompt = opts["prompt-file"].flatMap { try? String(contentsOfFile: $0, encoding: .utf8) }?
    .trimmingCharacters(in: .whitespacesAndNewlines)

// MARK: - Measurement helpers

func now() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e9 }

func cpuSeconds() -> Double {
    var ru = rusage(); getrusage(RUSAGE_SELF, &ru)
    return Double(ru.ru_utime.tv_sec + ru.ru_stime.tv_sec) + Double(ru.ru_utime.tv_usec + ru.ru_stime.tv_usec) / 1e6
}

func footprintMB() -> (current: Double, peak: Double) {
    var info = rusage_info_v4()
    let rc = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0) }
    }
    guard rc == 0 else { return (0, 0) }
    return (Double(info.ri_phys_footprint) / 1_048_576, Double(info.ri_lifetime_max_phys_footprint) / 1_048_576)
}

/// Cumulative Metal GPU time (seconds) for this process, from the GPU driver's per-client accounting.
func gpuSeconds() -> Double {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
    p.arguments = ["-r", "-c", "AGXDeviceUserClient", "-a"]
    let pipe = Pipe(); p.standardOutput = pipe
    guard (try? p.run()) != nil else { return 0 }
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
    guard let clients = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [[String: Any]] else { return 0 }
    let me = "pid \(getpid()),"
    var ns: UInt64 = 0
    for c in clients where (c["IOUserClientCreator"] as? String)?.hasPrefix(me) == true {
        for usage in c["AppUsage"] as? [[String: Any]] ?? [] { ns += (usage["accumulatedGPUTime"] as? UInt64) ?? 0 }
    }
    return Double(ns) / 1e9
}

func loadPCM16k(_ url: URL) throws -> [Float] {
    let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
    precondition(file.processingFormat.sampleRate == 16000 && file.processingFormat.channelCount == 1, "clips must be 16 kHz mono")
    let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
    try file.read(into: buf)
    return Array(UnsafeBufferPointer(start: buf.floatChannelData![0], count: Int(buf.frameLength)))
}

// MARK: - Engines

protocol Engine {
    func transcribe(_ pcm: [Float], url: URL) async throws -> String
    /// Must be called before exit: ggml's Metal backend asserts if a context outlives the process's static teardown.
    func close()
}
extension Engine { func close() {} }

final class WhisperEngine: Engine {
    let ctx: OpaquePointer
    init(path: String) {
        whisper_log_set({ _, _, _ in }, nil)
        var cp = whisper_context_default_params()
        cp.use_gpu = useGPU
        cp.flash_attn = useGPU
        guard let c = whisper_init_from_file_with_params(path, cp) else { fatalError("whisper: failed to load \(path)") }
        ctx = c
    }
    func transcribe(_ pcm: [Float], url: URL) async throws -> String {
        var p = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        p.n_threads = 4
        p.print_progress = false; p.print_realtime = false; p.print_timestamps = false; p.print_special = false
        p.no_timestamps = true
        var code = language
        if language == "auto3" {
            // Detection on the first 30 s, restricted to the three supported languages.
            _ = pcm.withUnsafeBufferPointer { whisper_pcm_to_mel(ctx, $0.baseAddress, Int32($0.count), 4) }
            var probs = [Float](repeating: 0, count: Int(whisper_lang_max_id()) + 1)
            _ = probs.withUnsafeMutableBufferPointer { whisper_lang_auto_detect(ctx, 0, 4, $0.baseAddress) }
            let candidates: [(String, Float)] = ["en", "de", "hi"].map { code in
                let id = code.withCString { whisper_lang_id($0) }
                return (code, probs[Int(id)])
            }
            code = candidates.max { $0.1 < $1.1 }!.0
            if opts["detect-only"] != nil || CommandLine.arguments.contains("--detect-only") {
                lastDetection = ["detected": code].merging(Dictionary(uniqueKeysWithValues: candidates.map { ("p_\($0.0)", Double($0.1)) })) { a, _ in a }
                return ""
            }
            lastDetection = ["detected": code] .merging(Dictionary(uniqueKeysWithValues: candidates.map { ("p_\($0.0)", Double($0.1)) })) { a, _ in a }
        }
        let lang = strdup(code), promptC = prompt.map { strdup($0) }
        defer { free(lang); promptC.map { free($0) } }
        p.language = UnsafePointer(lang)
        if let promptC { p.initial_prompt = UnsafePointer(promptC) }
        let rc = pcm.withUnsafeBufferPointer { whisper_full(ctx, p, $0.baseAddress, Int32($0.count)) }
        guard rc == 0 else { throw NSError(domain: "whisper", code: Int(rc)) }
        return (0..<whisper_full_n_segments(ctx)).map { String(cString: whisper_full_get_segment_text(ctx, $0)) }.joined()
    }
    func close() { whisper_free(ctx) }
}

final class ParakeetEngine: Engine {
    let ctx: OpaquePointer
    init(path: String) {
        var cp = parakeet_context_default_params()
        cp.use_gpu = useGPU
        guard let c = parakeet_init_from_file_with_params(path, cp) else { fatalError("parakeet: failed to load \(path)") }
        ctx = c
    }
    func transcribe(_ pcm: [Float], url: URL) async throws -> String {
        var p = parakeet_full_default_params(PARAKEET_SAMPLING_GREEDY)
        p.n_threads = 4
        let rc = pcm.withUnsafeBufferPointer { parakeet_full(ctx, p, $0.baseAddress, Int32($0.count)) }
        guard rc == 0 else { throw NSError(domain: "parakeet", code: Int(rc)) }
        return (0..<parakeet_full_n_segments(ctx)).map { String(cString: parakeet_full_get_segment_text(ctx, $0)) }.joined()
    }
    func close() { parakeet_free(ctx) }
}

final class AppleSpeechEngine: Engine {
    let locale: Locale
    let vocabulary: [String]
    init(locale: String) {
        self.locale = Locale(identifier: locale)
        vocabulary = prompt.map { $0.components(separatedBy: CharacterSet(charactersIn: ",\n")).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } } ?? []
    }
    func transcribe(_ pcm: [Float], url: URL) async throws -> String {
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [])
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            // One-time system download of the locale's on-device model (setup, not app runtime).
            try await request.downloadAndInstall()
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        if !vocabulary.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings[.general] = vocabulary
            try await analyzer.setContext(context)
        }
        let file = try AVAudioFile(forReading: url)
        let collector = Task { () -> String in
            var s = ""
            for try await r in transcriber.results where r.isFinal { s += String(r.text.characters) }
            return s
        }
        if let last = try await analyzer.analyzeSequence(from: file) {
            try await analyzer.finalizeAndFinish(through: last)
        } else {
            await analyzer.cancelAndFinishNow()
        }
        return try await collector.value
    }
}

// MARK: - Run

struct Corpus: Decodable { struct Entry: Decodable { let id: String }; let entries: [Entry] }

func jsonLine(_ dict: [String: Any]) -> String {
    String(data: try! JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]), encoding: .utf8)!
}

func run() async throws {
    let corpus = try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: URL(fileURLWithPath: opt("corpus"))))
    let audioDir = URL(fileURLWithPath: opt("audio-dir"))
    let clips = corpus.entries.map { ($0.id, audioDir.appendingPathComponent("\($0.id).wav")) }
        .filter { FileManager.default.fileExists(atPath: $0.1.path) }
    guard !clips.isEmpty else { fatalError("no clips in \(audioDir.path)") }

    let modelMB = (try? FileManager.default.attributesOfItem(atPath: modelArg)[.size] as? Double).map { $0 / 1_048_576 }
    let t0 = now()
    let engine: Engine = switch engineName {
    case "whisper": WhisperEngine(path: modelArg)
    case "parakeet": ParakeetEngine(path: modelArg)
    case "apple": AppleSpeechEngine(locale: modelArg)
    default: fatalError("unknown engine \(engineName)")
    }
    let loadS = now() - t0
    let afterLoad = footprintMB().current

    // Warm-up: the first transcription pays one-time costs (Metal pipelines, buffers, OS model load).
    let first = clips[0]
    let t1 = now()
    _ = try await engine.transcribe(try loadPCM16k(first.1), url: first.1)
    let firstRunS = now() - t1

    FileManager.default.createFile(atPath: opt("out"), contents: nil)
    let out = try FileHandle(forWritingTo: URL(fileURLWithPath: opt("out")))
    for (id, url) in clips {
        let pcm = try loadPCM16k(url)
        let gpu0 = gpuSeconds(), cpu0 = cpuSeconds(), s = now()
        lastDetection = nil
        let text = try await engine.transcribe(pcm, url: url)
        let latency = now() - s, cpu = cpuSeconds() - cpu0, gpu = gpuSeconds() - gpu0
        var line: [String: Any] = ["type": "clip", "run": runName, "id": id, "voice": voice,
                                   "audio_s": Double(pcm.count) / 16000, "latency_s": latency,
                                   "text": text.trimmingCharacters(in: .whitespacesAndNewlines)]
        if engineName != "apple" { line["cpu_s"] = cpu; line["gpu_s"] = gpu }
        if let lastDetection { line.merge(lastDetection) { a, _ in a } }
        out.write(Data((jsonLine(line) + "\n").utf8))
    }
    var summary: [String: Any] = ["type": "run", "run": runName, "load_s": loadS, "first_run_s": firstRunS,
                                  "footprint_after_load_mb": afterLoad, "peak_footprint_mb": footprintMB().peak]
    if let modelMB { summary["model_mb"] = modelMB }
    out.write(Data((jsonLine(summary) + "\n").utf8))
    try out.close()
    engine.close()
    print(String(format: "%@ [%@]: %d clips, load %.2fs, first run %.2fs, peak footprint %.0f MB",
                 runName, voice, clips.count, loadS, firstRunS, footprintMB().peak))
}

let semaphore = DispatchSemaphore(value: 0)
Task {
    do { try await run() } catch {
        FileHandle.standardError.write(Data("error: \(error)\n".utf8))
        exit(1)
    }
    semaphore.signal()
}
semaphore.wait()
