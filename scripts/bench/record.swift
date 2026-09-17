// Records human benchmark clips for the developer-speech corpus (developer tool, not part of the app).
//
//   record --corpus <json> --out <dir> [--category <name>] [--include-hinglish]
//
// For each entry: shows what to say, Enter starts recording, Enter stops, then
// [Enter] keep · [r] redo · [s] skip · [q] quit. Existing clips are skipped, so it resumes.
// Clips are 16 kHz mono 16-bit WAV, retained on purpose for benchmarking (gitignored).
import AVFoundation
import Foundation

var opts: [String: String] = [:]
var flags: Set<String> = []
do {
    let a = Array(CommandLine.arguments.dropFirst())
    var i = 0
    while i < a.count {
        if a[i].hasPrefix("--"), i + 1 < a.count, !a[i + 1].hasPrefix("--") { opts[String(a[i].dropFirst(2))] = a[i + 1]; i += 2 }
        else { flags.insert(String(a[i].dropFirst(2))); i += 1 }
    }
}

struct Corpus: Decodable {
    struct Entry: Decodable { let id, category, spoken, reference: String }
    let entries: [Entry]
}

final class Recorder {
    let engine = AVAudioEngine()
    let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
    private let lock = NSLock()
    private var samples: [Float] = []

    func start() throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: format, to: target) else { throw NSError(domain: "record", code: 1) }
        samples.removeAll(keepingCapacity: true)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * 16000 / format.sampleRate) + 16
            guard let out = AVAudioPCMBuffer(pcmFormat: self.target, frameCapacity: capacity) else { return }
            var fed = false
            _ = converter.convert(to: out, error: nil) { _, status in
                if fed { status.pointee = .noDataNow; return nil }
                fed = true; status.pointee = .haveData; return buffer
            }
            let chunk = UnsafeBufferPointer(start: out.floatChannelData![0], count: Int(out.frameLength))
            self.lock.lock(); self.samples.append(contentsOf: chunk); self.lock.unlock()
        }
        engine.prepare()
        try engine.start()
    }

    func stop() -> [Float] {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        lock.lock(); defer { lock.unlock() }
        return samples
    }

    func write(_ pcm: [Float], to url: URL) throws {
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000, AVNumberOfChannelsKey: 1,
                                       AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let buf = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: AVAudioFrameCount(pcm.count))!
        pcm.withUnsafeBufferPointer { buf.floatChannelData![0].update(from: $0.baseAddress!, count: pcm.count) }
        buf.frameLength = AVAudioFrameCount(pcm.count)
        try file.write(from: buf)
    }
}

func prompt(_ s: String) -> String { print(s, terminator: ""); fflush(stdout); return readLine() ?? "q" }

guard let corpusPath = opts["corpus"], let outPath = opts["out"] else {
    print("usage: record --corpus <json> --out <dir> [--category <name>] [--include-hinglish]"); exit(2)
}

let sem = DispatchSemaphore(value: 0)
AVCaptureDevice.requestAccess(for: .audio) { granted in
    if !granted { print("Microphone access denied. Allow your terminal app in System Settings → Privacy & Security → Microphone."); exit(1) }
    sem.signal()
}
sem.wait()

let corpus = try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: URL(fileURLWithPath: corpusPath)))
let outDir = URL(fileURLWithPath: outPath)
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
let entries = corpus.entries.filter { e in
    (opts["category"].map { $0 == e.category } ?? true) && (e.category != "hinglish" || flags.contains("include-hinglish") || opts["category"] == "hinglish")
}
let device = AVCaptureDevice.default(for: .audio)?.localizedName ?? "default input"
print("Input device: \(device)\nClips → \(outDir.path)\nSpeak naturally, as you would while dictating. Identifiers: say them as words (\"get user by id\").\n")

let recorder = Recorder()
var index = 0
while index < entries.count {
    let e = entries[index]
    let url = outDir.appendingPathComponent("\(e.id).wav")
    if FileManager.default.fileExists(atPath: url.path) { index += 1; continue }
    print("[\(index + 1)/\(entries.count)] \(e.id)\n  SAY:   \(e.spoken)\n  (want: \(e.reference))")
    if prompt("  Enter to start recording (s skip, q quit): ").lowercased().hasPrefix("q") { break }
    try recorder.start()
    _ = prompt("  🎙  Recording… Enter to stop: ")
    let pcm = recorder.stop()
    let seconds = Double(pcm.count) / 16000
    let peak = pcm.map(abs).max() ?? 0
    print(String(format: "  %.1fs, peak level %.2f%@", seconds, peak, peak < 0.02 ? "  ⚠︎ very quiet — check the mic" : ""))
    switch prompt("  [Enter] keep · [r] redo · [q] quit: ").lowercased() {
    case let c where c.hasPrefix("r"): continue
    case let c where c.hasPrefix("q"): exit(0)
    default: try recorder.write(pcm, to: url); index += 1
    }
}
print("Done.")
