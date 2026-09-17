import Foundation
import VoiceFlowCore

// vf-bench — scores STT benchmark output against the developer-speech corpus.
//
//   swift run vf-bench score benchmarks/corpus/developer-speech.json results/*.jsonl [--errors] [--by-voice]
//
// Input: JSONL written by scripts/bench/stt_engines.swift. Each line is either a
// transcription {"type":"clip",...} or a per-run summary {"type":"run",...}.

struct Line: Decodable {
    var type: String
    var run: String
    // clip
    var id: String?
    var voice: String?
    var audio_s: Double?
    var latency_s: Double?
    var cpu_s: Double?
    var gpu_s: Double?
    var text: String?
    // run
    var load_s: Double?
    var first_run_s: Double?
    var model_mb: Double?
    var footprint_after_load_mb: Double?
    var peak_footprint_mb: Double?
}

func fmt(_ v: Double?, _ digits: Int = 2) -> String { v.map { String(format: "%.\(digits)f", $0) } ?? "—" }
func pct(_ v: Double) -> String { String(format: "%.1f%%", v * 100) }
func percentile(_ xs: [Double], _ p: Double) -> Double? {
    guard !xs.isEmpty else { return nil }
    let s = xs.sorted(); return s[min(s.count - 1, Int((Double(s.count - 1) * p).rounded()))]
}

let args = Array(CommandLine.arguments.dropFirst())
guard args.first == "score", args.count >= 3 else {
    FileHandle.standardError.write(Data("usage: vf-bench score <corpus.json> <results.jsonl>... [--errors]\n".utf8))
    exit(2)
}
let showErrors = args.contains("--errors")
let byVoice = args.contains("--by-voice")
let files = args.dropFirst(2).filter { !$0.hasPrefix("--") }
let corpus = try BenchmarkCorpus.load(from: URL(fileURLWithPath: args[1]))
let entries = Dictionary(uniqueKeysWithValues: corpus.entries.map { ($0.id, $0) })

var clips: [String: [Line]] = [:]
var runs: [String: Line] = [:]
var order: [String] = []
let decoder = JSONDecoder()
for file in files {
    for raw in try String(contentsOfFile: file, encoding: .utf8).split(separator: "\n") where !raw.isEmpty {
        var line = try decoder.decode(Line.self, from: Data(raw.utf8))
        if byVoice, line.type == "clip" { line.run += " · " + (line.voice ?? "?") }
        if !order.contains(line.run) { order.append(line.run) }
        if line.type == "clip" { clips[line.run, default: []].append(line); continue }
        // One summary per process (per voice); keep the worst case of each measurement.
        if var r = runs[line.run] {
            r.load_s = max(r.load_s ?? 0, line.load_s ?? 0)
            r.first_run_s = max(r.first_run_s ?? 0, line.first_run_s ?? 0)
            r.footprint_after_load_mb = max(r.footprint_after_load_mb ?? 0, line.footprint_after_load_mb ?? 0)
            r.peak_footprint_mb = max(r.peak_footprint_mb ?? 0, line.peak_footprint_mb ?? 0)
            runs[line.run] = r
        } else {
            runs[line.run] = line
        }
    }
}

let categories = BenchmarkCorpus.Category.allCases.filter { c in clips.values.joined().contains { entries[$0.id ?? ""]?.category == c } }

print("## Accuracy\n")
print("WER = word error rate vs the spoken words, spelling-agnostic (lower is better). Terms = key terms heard correctly in any spelling. Exact = canonical spelling in raw output. Fmt WER = case/punctuation-sensitive.\n")
print("| Run | Clips | WER | " + categories.map { "WER \($0.rawValue)" }.joined(separator: " | ") + " | Terms | Exact | Fmt WER |")
print("|" + String(repeating: "---|", count: 6 + categories.count))
var errorReport: [String] = []
for run in order {
    guard let lines = clips[run] else { continue }
    var total = EditCounts(), formatted = EditCounts()
    var perCategory: [BenchmarkCorpus.Category: EditCounts] = [:]
    var termsTotal = 0, termsHit = 0, termsExact = 0
    for l in lines {
        guard let e = entries[l.id ?? ""] else { continue }
        let s = AccuracyScorer.score(reference: e.reference, spoken: e.spoken, hypothesis: l.text ?? "", terms: e.terms)
        total = total + s.words; formatted = formatted + s.formatted
        perCategory[e.category, default: EditCounts()] = perCategory[e.category, default: EditCounts()] + s.words
        termsTotal += e.terms.count; termsHit += s.recognizedTerms.count; termsExact += s.exactTerms.count
        if showErrors && (s.words.errors > 0 || !s.missedTerms.isEmpty) {
            errorReport.append("- **\(run)** `\(e.id)` [\(l.voice ?? "")] WER \(pct(s.words.rate))"
                + (s.missedTerms.isEmpty ? "" : " · missed: \(s.missedTerms.joined(separator: ", "))")
                + "\n  - ref: \(e.reference)\n  - hyp: \(l.text ?? "")")
        }
    }
    let catCols = categories.map { perCategory[$0].map { pct($0.rate) } ?? "—" }
    let termRate = termsTotal == 0 ? 0 : Double(termsHit) / Double(termsTotal)
    let exactRate = termsTotal == 0 ? 0 : Double(termsExact) / Double(termsTotal)
    print("| \(run) | \(lines.count) | **\(pct(total.rate))** | " + catCols.joined(separator: " | ")
          + " | **\(pct(termRate))** (\(termsHit)/\(termsTotal)) | \(pct(exactRate)) | \(pct(formatted.rate)) |")
}

print("\n## Performance\n")
print("Latency = warm transcription wall time per clip. RTF = latency ÷ audio duration. CPU/GPU = process CPU time and Metal GPU time per clip (Apple Speech runs in a system daemon: not captured).\n")
print("Load s and First run s are the worst case across processes (the first process after a new build includes one-time Metal shader compilation).\n")
print("| Run | Model MB | Load s | First run s | Mean latency s | p95 latency s | Max latency s | Mean RTF | CPU s/clip | GPU s/clip | Footprint after load MB | Peak footprint MB |")
print("|---|---|---|---|---|---|---|---|---|---|---|---|")
for run in order {
    guard let lines = clips[run] else { continue }
    let lat = lines.compactMap(\.latency_s)
    let rtf = lines.compactMap { l in l.latency_s.flatMap { lat in l.audio_s.map { lat / $0 } } }
    let cpu = lines.compactMap(\.cpu_s), gpu = lines.compactMap(\.gpu_s)
    let mean: ([Double]) -> Double? = { $0.isEmpty ? nil : $0.reduce(0, +) / Double($0.count) }
    let r = runs[run] ?? runs[String(run.split(separator: " · ").first ?? "")]
    print("| \(run) | \(fmt(r?.model_mb, 0)) | \(fmt(r?.load_s)) | \(fmt(r?.first_run_s)) | \(fmt(mean(lat), 3)) | \(fmt(percentile(lat, 0.95), 3)) | \(fmt(lat.max(), 3)) | \(fmt(mean(rtf), 3)) | \(fmt(mean(cpu), 3)) | \(fmt(mean(gpu), 3)) | \(fmt(r?.footprint_after_load_mb, 0)) | \(fmt(r?.peak_footprint_mb, 0)) |")
}

if showErrors {
    print("\n## Errors\n")
    print(errorReport.joined(separator: "\n"))
}
