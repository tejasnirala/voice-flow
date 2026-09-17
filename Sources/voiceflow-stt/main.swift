import Darwin
import Foundation
import os
import VoiceFlowCore

// voiceflow-stt — the only VoiceFlow process that loads whisper.cpp (Metal / Core ML).
//
// Launched by the app when dictation starts; talks over stdin/stdout using `SpeechHelperWire` frames. It exits on
// `.shutdown` or when stdin closes (the app quit or crashed), so every byte of model memory, including allocations
// whisper.cpp never frees, returns to the system.
//
// Developer mode: `voiceflow-stt --transcribe-benchmark <audio-dir> --corpus <json> --out <jsonl> [--run name] [--voice label]`

let log = Logger(subsystem: "local.voiceflow.VoiceFlow", category: "speech-helper")

// ggml's Metal residency sets start a thread that wakes every 5 ms for the process lifetime (PERFORMANCE.md §3.4).
if ProcessInfo.processInfo.environment["VOICEFLOW_METAL_RESIDENCY"] != "1" {
    setenv("GGML_METAL_NO_RESIDENCY", "1", 1)
}
// A write to a closed pipe must fail with an error, not kill the process.
signal(SIGPIPE, SIG_IGN)

if CommandLine.arguments.contains("--transcribe-benchmark") {
    exit(BenchmarkMode.run(arguments: CommandLine.arguments))
}

let input = FileHandle.standardInput
let output = FileHandle.standardOutput
/// Loaded models by file path. Auto language uses a detector and a transcription model at the same time.
var engines: [String: WhisperEngine] = [:]

func reply(_ message: SpeechHelperMessage) -> Bool {
    do {
        try output.write(contentsOf: SpeechHelperWire.encode(message))
        return true
    } catch {
        log.error("reply failed: \(error.localizedDescription, privacy: .public)")
        return false
    }
}

log.notice("helper started, pid \(getpid(), privacy: .public)")
serve: while true {
    let message: SpeechHelperMessage
    do {
        message = try SpeechHelperWire.decode(read: { try input.readExactly($0) })
    } catch {
        break serve // stdin closed: the app is gone
    }
    switch message {
    case .prepare(let request):
        let active = engines[request.modelPath] ?? WhisperEngine(request)
        engines[request.modelPath] = active
        do {
            let seconds = try active.prepare()
            guard reply(.ready(.init(loadSeconds: seconds, encoder: active.encoderName))) else { break serve }
        } catch {
            engines[request.modelPath] = nil
            guard reply(.failure(error.localizedDescription)) else { break serve }
        }
    case .transcribe(let options, let samples):
        let active = engines[options.modelPath]
            ?? WhisperEngine(modelPath: options.modelPath, modelFileName: options.modelFileName, language: options.language, prompt: options.prompt)
        engines[options.modelPath] = active
        do {
            let r = try active.transcribe(samples, language: options.language, prompt: options.prompt)
            guard reply(.transcription(.init(text: r.text, audioSeconds: r.audioSeconds, transcribeSeconds: r.transcribeSeconds,
                                             chunkCount: r.chunkCount, transcribedAudioSeconds: r.transcribedAudioSeconds))) else { break serve }
        } catch {
            guard reply(.failure(error.localizedDescription)) else { break serve }
        }
    case .detectLanguage(let options, let samples):
        let active = engines[options.modelPath]
            ?? WhisperEngine(modelPath: options.modelPath, modelFileName: options.modelFileName, language: "en", prompt: nil)
        engines[options.modelPath] = active
        do {
            let (probabilities, seconds) = try active.detectLanguage(samples, candidates: options.candidates)
            guard reply(.detection(.init(probabilities: probabilities, seconds: seconds))) else { break serve }
        } catch {
            guard reply(.failure(error.localizedDescription)) else { break serve }
        }
    case .shutdown:
        break serve
    case .ready, .transcription, .detection, .failure:
        guard reply(.failure("Unexpected message")) else { break serve }
    }
}
for engine in engines.values { engine.unload() }
log.notice("helper exiting, footprint \(ResourceUsage.footprintMB, format: .fixed(precision: 0), privacy: .public) MB")
exit(0)
