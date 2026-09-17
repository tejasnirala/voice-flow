import Foundation
import VoiceFlowCore

// vf-bench — scores STT benchmark output against the developer-speech corpus.
//
//   swift run vf-bench score benchmarks/corpus/developer-speech.json results/*.jsonl [--errors] [--by-voice]
//                            [--overrides-dir benchmarks-output/audio/human]
//
// --overrides-dir: for each voice, `<dir>/<voice>/spoken-overrides.json` ({"clip-id": "what was actually
// said"}) replaces the corpus `spoken` text for that recording. It's for human-reviewed corrections when the
// speaker deviated from the script, so a model isn't penalized for transcribing what was really said.
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

var args = Array(CommandLine.arguments.dropFirst())
// --hinglish: tolerate romanized Hindi spelling variants when scoring (TranscriptNormalizer.romanizedHindi).
if let index = args.firstIndex(of: "--hinglish") { TranscriptNormalizer.romanizedHindi = true; args.remove(at: index) }
// `vf-bench hindi-script <results.jsonl> --to hinglish|devanagari --run <name>`: rewrites transcripts with the Phase 14
// conversions (Devanagari → Hinglish, or Devanagari loanwords → Latin) so they can be scored against the other corpus.
if args.first == "hindi-script" {
    let file = args[1]
    let to = args.firstIndex(of: "--to").map { args[$0 + 1] } ?? "hinglish"
    let run = args.firstIndex(of: "--run").map { args[$0 + 1] }
    for raw in try String(contentsOfFile: file, encoding: .utf8).split(separator: "\n") where !raw.isEmpty {
        guard var object = try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any] else { continue }
        if let text = object["text"] as? String {
            object["text"] = to == "hinglish" ? HindiTransliteration.hinglish(text) : HindiTransliteration.latinizeLoanwords(text)
        }
        if let run { object["run"] = run }
        print(String(data: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), encoding: .utf8)!)
    }
    exit(0)
}

if args.first == "modes" {
    exit(try runModes(Array(args.dropFirst())))
}
if args.first == "cleanup" {
    exit(try runCleanupReport(Array(args.dropFirst())))
}
guard args.first == "score", args.count >= 3 else {
    FileHandle.standardError.write(Data("usage: vf-bench score <corpus.json> <results.jsonl>... [--errors]\n".utf8))
    exit(2)
}
let showErrors = args.contains("--errors")
let byVoice = args.contains("--by-voice")
let overridesDir = args.firstIndex(of: "--overrides-dir").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
let files = args.dropFirst(2).filter { !$0.hasPrefix("--") && $0 != overridesDir }

var overrideCache: [String: [String: String]] = [:]
@MainActor func spokenText(for entry: BenchmarkCorpus.Entry, voice: String?) -> (text: String, overridden: Bool) {
    guard let dir = overridesDir, let voice else { return (entry.spoken, false) }
    if overrideCache[voice] == nil {
        let url = URL(fileURLWithPath: dir).appendingPathComponent(voice).appendingPathComponent("spoken-overrides.json")
        overrideCache[voice] = (try? JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))) ?? [:]
    }
    if let text = overrideCache[voice]?[entry.id] { return (text, true) }
    return (entry.spoken, false)
}
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
print("| Run | Clips | WER | " + categories.map { "WER \($0.rawValue)" }.joined(separator: " | ") + " | Terms | Exact | Fmt WER | Invented phrases |")
print("|" + String(repeating: "---|", count: 7 + categories.count))
var errorReport: [String] = []
var termsByCategory: [String: [BenchmarkCorpus.Category: (hit: Int, total: Int)]] = [:]
for run in order {
    guard let lines = clips[run] else { continue }
    var total = EditCounts(), formatted = EditCounts()
    var perCategory: [BenchmarkCorpus.Category: EditCounts] = [:]
    var termsTotal = 0, termsHit = 0, termsExact = 0, inventedPhrases = 0
    for l in lines {
        guard let e = entries[l.id ?? ""] else { continue }
        let spoken = spokenText(for: e, voice: l.voice)
        let s = AccuracyScorer.score(reference: e.reference, spoken: spoken.text, hypothesis: l.text ?? "", terms: e.terms)
        termsByCategory[run, default: [:]][e.category, default: (0, 0)].hit += s.recognizedTerms.count
        termsByCategory[run, default: [:]][e.category, default: (0, 0)].total += e.terms.count
        total = total + s.words; formatted = formatted + s.formatted
        perCategory[e.category, default: EditCounts()] = perCategory[e.category, default: EditCounts()] + s.words
        termsTotal += e.terms.count; termsHit += s.recognizedTerms.count; termsExact += s.exactTerms.count
        inventedPhrases += s.insertedPhrases.count
        if showErrors && (s.words.errors > 0 || !s.missedTerms.isEmpty || !s.insertedPhrases.isEmpty) {
            errorReport.append("- **\(run)** `\(e.id)` [\(l.voice ?? "")] WER \(pct(s.words.rate))"
                + (spoken.overridden ? " (reviewed reference)" : "")
                + (s.missedTerms.isEmpty ? "" : " · missed: \(s.missedTerms.joined(separator: ", "))")
                + (s.insertedPhrases.isEmpty ? "" : " · invented: \(s.insertedPhrases.map { "\"\($0)\"" }.joined(separator: ", "))")
                + "\n  - ref: \(e.reference)\n  - hyp: \(l.text ?? "")")
        }
    }
    let catCols = categories.map { perCategory[$0].map { pct($0.rate) } ?? "—" }
    let termRate = termsTotal == 0 ? 0 : Double(termsHit) / Double(termsTotal)
    let exactRate = termsTotal == 0 ? 0 : Double(termsExact) / Double(termsTotal)
    print("| \(run) | \(lines.count) | **\(pct(total.rate))** | " + catCols.joined(separator: " | ")
          + " | **\(pct(termRate))** (\(termsHit)/\(termsTotal)) | \(pct(exactRate)) | \(pct(formatted.rate)) | \(inventedPhrases) (\(String(format: "%.1f", Double(inventedPhrases) * 100 / Double(lines.count))) per 100) |")
}

print("\n### Term recognition by category\n")
let termCategories = categories.filter { c in termsByCategory.values.contains { ($0[c]?.total ?? 0) > 0 } }
print("| Run | " + termCategories.map(\.rawValue).joined(separator: " | ") + " |")
print("|" + String(repeating: "---|", count: 1 + termCategories.count))
for run in order where clips[run] != nil {
    let cols = termCategories.map { c -> String in
        guard let t = termsByCategory[run]?[c], t.total > 0 else { return "—" }
        return "\(pct(Double(t.hit) / Double(t.total))) (\(t.hit)/\(t.total))"
    }
    print("| \(run) | " + cols.joined(separator: " | ") + " |")
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


// MARK: - Smart Mode cleanup report

/// `vf-bench cleanup <cleanup-corpus.json> <results.jsonl>... [--errors]`
/// Results lines: {"type":"clip","run","id","output","latency_s","output_tokens"?}
func runCleanupReport(_ args: [String]) throws -> Int32 {
    struct Entry: Decodable { let id, category, input, reference: String; let terms: [String] }
    struct Corpus: Decodable { let entries: [Entry] }
    struct Result: Decodable { let type: String; let run: String; let id: String?; let output: String?; let latency_s: Double?; let output_tokens: Int? }
    guard args.count >= 2 else {
        FileHandle.standardError.write(Data("usage: vf-bench cleanup <corpus.json> <results.jsonl>... [--errors]\n".utf8)); return 2
    }
    let showErrors = args.contains("--errors")
    // --guarded: also report each run as the app would ship it, with unsafe outputs replaced by the raw transcript.
    let guarded = args.contains("--guarded")
    // --rule-based: add a run for the deterministic RuleBasedCleanup (no LLM).
    let ruleBased = args.contains("--rule-based")
    let corpus = try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: URL(fileURLWithPath: args[0])))
    let entries = Dictionary(uniqueKeysWithValues: corpus.entries.map { ($0.id, $0) })
    var order: [String] = []
    var results: [String: [Result]] = [:]
    for file in args.dropFirst().filter({ !$0.hasPrefix("--") }) {
        for raw in try String(contentsOfFile: file, encoding: .utf8).split(separator: "\n") where !raw.isEmpty {
            let r = try JSONDecoder().decode(Result.self, from: Data(raw.utf8))
            guard r.type == "clip" else { continue }
            if !order.contains(r.run) { order.append(r.run) }
            results[r.run, default: []].append(r)
        }
    }
    if ruleBased {
        order.insert("rule-based cleanup (no LLM)", at: 0)
        results["rule-based cleanup (no LLM)"] = corpus.entries.map {
            let t = DispatchTime.now().uptimeNanoseconds
            let out = RuleBasedCleanup.clean($0.input)
            return Result(type: "clip", run: "rule-based cleanup (no LLM)", id: $0.id, output: out,
                          latency_s: Double(DispatchTime.now().uptimeNanoseconds - t) / 1e9, output_tokens: nil)
        }
    }
    if guarded {
        for run in order where !run.hasPrefix("rule-based") && !run.hasPrefix("fast-mode") {
            let name = run + " + guard"
            results[name] = (results[run] ?? []).map { r in
                guard let e = entries[r.id ?? ""] else { return r }
                let s = CleanupScorer.score(input: e.input, output: r.output ?? "", reference: e.reference, terms: e.terms)
                return s.isUnsafe ? Result(type: r.type, run: name, id: r.id, output: e.input, latency_s: r.latency_s, output_tokens: r.output_tokens) : r
            }
            order.append(name)
        }
    }
    let categories = Array(Set(corpus.entries.map { $0.category.hasPrefix("stt-") ? "stt" : $0.category })).sorted()
    print("## Smart Mode cleanup\n")
    print("Unsafe = invented phrase, dropped term, dropped content word, or code fence. Fmt WER = case/punctuation-sensitive error vs the ideal written text (input → output).\n")
    print("| Run | Entries | **Unsafe** | Invented phrases | Dropped terms | Dropped content words | Added words | Fmt WER in → out | " + categories.map { "Unsafe \($0)" }.joined(separator: " | ") + " | Mean latency s | p95 s |")
    print("|" + String(repeating: "---|", count: 10 + categories.count))
    var errors: [String] = []
    for run in order {
        let rs = (results[run] ?? []).filter { entries[$0.id ?? ""] != nil }
        var unsafe = 0, invented = 0, droppedTerms = 0, droppedWords = 0, added = 0
        var before = EditCounts(), after = EditCounts()
        var unsafeByCategory: [String: Int] = [:]
        for r in rs {
            guard let e = entries[r.id ?? ""] else { continue }
            let s = CleanupScorer.score(input: e.input, output: r.output ?? "", reference: e.reference, terms: e.terms)
            before = before + s.formattingBefore; after = after + s.formattingAfter
            invented += s.inventedPhrases.count; droppedTerms += s.droppedTerms.count
            droppedWords += s.droppedContentWords.count; added += s.addedWords
            let cat = e.category.hasPrefix("stt-") ? "stt" : e.category
            if s.isUnsafe {
                unsafe += 1; unsafeByCategory[cat, default: 0] += 1
                if showErrors {
                    var why: [String] = []
                    if !s.inventedPhrases.isEmpty { why.append("invented: " + s.inventedPhrases.map { "\"\($0)\"" }.joined(separator: ", ")) }
                    if !s.droppedTerms.isEmpty { why.append("dropped terms: " + s.droppedTerms.joined(separator: ", ")) }
                    if !s.droppedContentWords.isEmpty { why.append("dropped words: " + s.droppedContentWords.joined(separator: " ")) }
                    if !s.substitutedWords.isEmpty { why.append("replaced: " + s.substitutedWords.joined(separator: " ")) }
                    if s.expanded { why.append("expanded") }
                    if s.hasCodeFence { why.append("code fence") }
                    errors.append("- **\(run)** `\(e.id)` · \(why.joined(separator: " · "))\n  - in:  \(e.input)\n  - out: \((r.output ?? "").replacingOccurrences(of: "\n", with: " ⏎ "))")
                }
            }
        }
        let lat = rs.compactMap(\.latency_s).sorted()
        let mean = lat.isEmpty ? 0 : lat.reduce(0, +) / Double(lat.count)
        let p95 = lat.isEmpty ? 0 : lat[min(lat.count - 1, Int((Double(lat.count - 1) * 0.95).rounded()))]
        let catCols = categories.map { "\(unsafeByCategory[$0] ?? 0)" }
        print("| \(run) | \(rs.count) | **\(unsafe)** | \(invented) | \(droppedTerms) | \(droppedWords) | \(added) | \(pct(before.rate)) → \(pct(after.rate)) | "
              + catCols.joined(separator: " | ") + String(format: " | %.3f | %.3f |", mean, p95))
    }
    if showErrors { print("\n## Unsafe outputs\n"); print(errors.joined(separator: "\n")) }
    return 0
}

// MARK: - Text modes (Phase 8)

/// `vf-bench modes prepare <corpus.json>... --mode <mode> --out <file.json>`
///   Writes the corpus with each input replaced by `TextProcessingPlan.prepare(input, mode:)`, for scripts/bench/llm_apple.
/// `vf-bench modes report <corpus.json>... [--results <run.jsonl>]... [--show]`
///   Deterministic modes (raw, clean, developer) are computed here. Model runs come from JSONL whose run name starts
///   with the mode ("prompt/apple", "developer/apple"); each output goes through the mode's guard as in the app.
func runModes(_ args: [String]) throws -> Int32 {
    struct Entry: Codable { let id, category, input, reference: String; let terms: [String] }
    struct Corpus: Codable { var version = 1; var entries: [Entry] }
    struct Result: Decodable { let type: String; let run: String; let id: String?; let output: String?; let latency_s: Double? }
    func values(_ flag: String) -> [String] { args.indices.filter { args[$0] == flag && $0 + 1 < args.count }.map { args[$0 + 1] } }
    let flagged = Set(args.indices.filter { args[$0].hasPrefix("--") && args[$0] != "--show" }.map { $0 + 1 })
    let corpusFiles = args.dropFirst().indices.filter { !args[$0].hasPrefix("--") && !flagged.contains($0) }.map { args[$0] }
    if args.first == "intel" { return try runIntel(corpusFiles) }
    var entries: [Entry] = []
    for file in corpusFiles { entries += try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: URL(fileURLWithPath: file))).entries }
    let terms = RewriteGuard.terms(fromVocabulary: DeveloperVocabulary.prompt())
    // --language english|german|hindiDevanagari|hinglish: language-aware cleanup (Phase 14).
    let language = values("--language").first.flatMap(OutputLanguage.init(rawValue:)) ?? .english

    switch args.first {
    case "prepare":
        guard let raw = values("--mode").first, let mode = TextMode(rawValue: raw), let out = values("--out").first else { return 2 }
        let prepared = entries.map { Entry(id: $0.id, category: $0.category, input: TextProcessingPlan.prepare($0.input, mode: mode, language: language),
                                           reference: $0.reference, terms: $0.terms) }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(Corpus(entries: prepared)).write(to: URL(fileURLWithPath: out))
        print("wrote \(prepared.count) entries (\(raw)) to \(out)")
        return 0
    case "report":
        break
    default:
        FileHandle.standardError.write(Data("usage: vf-bench modes prepare|report <corpus.json>... (see source)\n".utf8)); return 2
    }
    let show = args.contains("--show")
    let byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
    // Spoken separators are removed before safety scoring so "package dot json" → "package.json" counts as no change.
    func unspoken(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).filter { !["dot", "dash", "hyphen", "underscore", "slash"].contains($0.lowercased()) }
            .joined(separator: " ")
    }
    var details: [String] = []

    print("## Deterministic modes (\(entries.count) entries)\n")
    print("Unsafe = invented phrase, dropped term or content word, replaced word, expansion or code fence vs the raw transcript (spoken separators ignored). Fmt WER = case/punctuation-sensitive error vs the ideal written text.\n")
    print("| Mode | Changed | **Unsafe** | Fmt WER | Mean latency ms | Max ms |")
    print("|---|---|---|---|---|---|")
    for mode in [TextMode.raw, .clean, .developer] {
        var changed = 0, unsafe = 0, after = EditCounts(), times: [Double] = []
        for e in entries {
            let t = DispatchTime.now().uptimeNanoseconds
            let out = TextProcessingPlan.prepare(e.input, mode: mode, language: language)
            times.append(Double(DispatchTime.now().uptimeNanoseconds - t) / 1e6)
            let s = CleanupScorer.score(input: unspoken(e.input), output: unspoken(out), reference: e.reference, terms: e.terms)
            after = after + s.formattingAfter
            if out != e.input { changed += 1 }
            if s.isUnsafe { unsafe += 1 }
            if show, mode == .developer, out != TextProcessingPlan.prepare(e.input, mode: .clean) {
                details.append("- developer `\(e.id)`\(s.isUnsafe ? " **UNSAFE**" : "")\n  - clean:     \(TextProcessingPlan.prepare(e.input, mode: .clean))\n  - developer: \(out)")
            }
        }
        print("| \(mode.displayName) | \(changed) | **\(unsafe)** | \(pct(after.rate)) | \(String(format: "%.3f", times.reduce(0, +) / Double(max(times.count, 1)))) | \(String(format: "%.3f", times.max() ?? 0)) |")
    }

    var runs: [String] = [], results: [String: [Result]] = [:]
    for file in values("--results") {
        for raw in try String(contentsOfFile: file, encoding: .utf8).split(separator: "\n") where !raw.isEmpty {
            let r = try JSONDecoder().decode(Result.self, from: Data(raw.utf8))
            guard r.type == "clip" else { continue }
            if !runs.contains(r.run) { runs.append(r.run) }
            results[r.run, default: []].append(r)
        }
    }
    if !runs.isEmpty {
        print("\n## Model rewrite modes (on-device model + mode guard)\n")
        print("Accepted = the model output passed the mode's guard and is pasted; otherwise the prepared text is pasted. Shipped unsafe = unsafe vs the raw transcript after the guard (strict scoring; restructuring in Prompt/Writing shows here as a content-order change, reviewed by hand below).\n")
        print("| Run | Guard | Entries | Accepted | Fallback | Rejections by reason | Fmt WER prepared → shipped | Mean latency s | p95 s |")
        print("|---|---|---|---|---|---|---|---|---|")
    }
    for run in runs {
        guard let mode = TextMode(rawValue: String(run.prefix { $0 != "/" })) else { continue }
        let rs = (results[run] ?? []).filter { byID[$0.id ?? ""] != nil }
        var accepted = 0, reasons: [String: Int] = [:], before = EditCounts(), after = EditCounts()
        for r in rs {
            let e = byID[r.id!]!
            let prepared = TextProcessingPlan.prepare(e.input, mode: mode, language: language)
            let rewrite = (r.output ?? "").isEmpty ? nil : r.output
            let (text, verdict) = TextProcessingPlan.finalText(prepared: prepared, rewrite: rewrite, terms: terms + e.terms.map { String($0.prefix { $0 != "|" }) }, mode: mode)
            before = before + AccuracyScorer.editCounts(reference: AccuracyScorer.formattedTokens(e.reference), hypothesis: AccuracyScorer.formattedTokens(prepared))
            after = after + AccuracyScorer.editCounts(reference: AccuracyScorer.formattedTokens(e.reference), hypothesis: AccuracyScorer.formattedTokens(text))
            switch verdict {
            case .accept?:
                accepted += 1
                if show, text != prepared {
                    details.append("- \(run) `\(e.id)` accepted\n  - prepared: \(prepared)\n  - shipped:  \(text.replacingOccurrences(of: "\n", with: " ⏎ "))")
                }
            case .reject(let why)?:
                why.forEach { reasons[$0, default: 0] += 1 }
                if show {
                    details.append("- \(run) `\(e.id)` rejected (\(why.joined(separator: ", ")))\n  - prepared: \(prepared)\n  - model:    \((r.output ?? "").replacingOccurrences(of: "\n", with: " ⏎ "))")
                }
            case nil:
                reasons["no output", default: 0] += 1
            }
        }
        let lat = rs.compactMap(\.latency_s)
        let why = reasons.sorted { $0.value > $1.value }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
        print("| \(run) | \(mode.guardPolicy) | \(rs.count) | \(accepted) | \(pct(Double(rs.count - accepted) / Double(max(rs.count, 1)))) | \(why.isEmpty ? "—" : why) | \(pct(before.rate)) → \(pct(after.rate)) | \(fmt(lat.isEmpty ? nil : lat.reduce(0, +) / Double(lat.count), 3)) | \(fmt(percentile(lat, 0.95), 3)) |")
    }
    if show, !details.isEmpty { print("\n## Details\n"); print(details.joined(separator: "\n")) }
    return 0
}

/// `vf-bench modes intel <developer-intel.json>...` (Phase 9): exact match per category for Developer/Code mode entries;
/// traps must equal Clean mode's output (any difference is an over-correction).
func runIntel(_ files: [String]) throws -> Int32 {
    struct Entry: Decodable { let id, category, mode, input, reference: String }
    struct Corpus: Decodable { let entries: [Entry] }
    var entries: [Entry] = []
    for file in files { entries += try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: URL(fileURLWithPath: file))).entries }
    var byCategory: [String: (exact: Int, total: Int)] = [:]
    var overCorrections = 0, failures: [String] = []
    for e in entries {
        let mode = TextMode(rawValue: e.mode) ?? .developer
        let out = TextProcessingPlan.prepare(e.input, mode: mode)
        let clean = TextProcessingPlan.prepare(e.input, mode: .clean)
        var cell = byCategory[e.category] ?? (0, 0)
        cell.total += 1
        if out == e.reference { cell.exact += 1 }
        byCategory[e.category] = cell
        if e.category == "trap", out != clean { overCorrections += 1 }
        if out != e.reference { failures.append("- `\(e.id)` (\(mode.rawValue))\n  - expected: \(e.reference)\n  - got:      \(out)") }
    }
    print("## Developer intelligence (\(entries.count) entries)\n")
    print("| Category | Exact | Total |")
    print("|---|---|---|")
    for (category, cell) in byCategory.sorted(by: { $0.key < $1.key }) { print("| \(category) | \(cell.exact) | \(cell.total) |") }
    print("\nOver-corrections (trap output differs from Clean): **\(overCorrections)**")
    if !failures.isEmpty { print("\n## Not exact\n"); print(failures.joined(separator: "\n")) }
    return 0
}
