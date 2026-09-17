// Smart Mode benchmark harness for Apple's on-device Foundation Model (developer tool, not part of the app).
//   swiftc -O scripts/bench/llm_apple.swift -o benchmarks-output/bin/llm_apple
//   benchmarks-output/bin/llm_apple benchmarks-output/cleanup-corpus.json prompts/clean.json <out.jsonl> [run-name]
// Each entry gets a fresh session (no carry-over), greedy sampling. Writes JSONL for `vf-bench cleanup`.
import Foundation
import FoundationModels

struct Entry: Decodable { let id, input: String }
struct Corpus: Decodable { let entries: [Entry] }
struct Prompt: Decodable { struct Example: Decodable { let input, output: String }; let system: String; let examples: [Example] }

let args = CommandLine.arguments
let corpus = try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
let prompt = try JSONDecoder().decode(Prompt.self, from: Data(contentsOf: URL(fileURLWithPath: args[2])))
let outPath = args[3]
let run = args.count > 4 ? args[4] : "apple-foundation-model"
let instructions = prompt.system + "\n\nExamples:\n" + prompt.examples.map { "Transcript: \($0.input)\nRewritten: \($0.output)" }.joined(separator: "\n\n")

func now() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e9 }
let semaphore = DispatchSemaphore(value: 0)
Task {
    FileManager.default.createFile(atPath: outPath, contents: nil)
    let out = try! FileHandle(forWritingTo: URL(fileURLWithPath: outPath))
    guard case .available = SystemLanguageModel.default.availability else {
        print("model unavailable: \(SystemLanguageModel.default.availability)"); exit(1)
    }
    // Warm-up (first use loads the model).
    let warm = now()
    _ = try? await LanguageModelSession(instructions: instructions).respond(to: "uh hello there", options: GenerationOptions(samplingMode: .greedy))
    print(String(format: "warm-up %.2f s", now() - warm))
    for e in corpus.entries {
        let session = LanguageModelSession(instructions: instructions)
        let t = now()
        var line: [String: Any] = ["type": "clip", "run": run, "id": e.id]
        do {
            let response = try await session.respond(to: e.input, options: GenerationOptions(samplingMode: .greedy))
            line["output"] = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            line["output"] = ""
            line["error"] = String(describing: error)
        }
        line["latency_s"] = now() - t
        try! out.write(contentsOf: JSONSerialization.data(withJSONObject: line, options: [.sortedKeys]) + Data("\n".utf8))
    }
    try? out.close()
    semaphore.signal()
}
semaphore.wait()
