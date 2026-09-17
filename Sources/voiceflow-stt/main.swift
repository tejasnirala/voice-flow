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
var engine: WhisperEngine?

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
        if let current = engine,
           current.modelPath != request.modelPath || current.prompt != request.prompt || current.language != request.language {
            current.unload()
            engine = nil
        }
        let active = engine ?? WhisperEngine(request)
        engine = active
        do {
            let seconds = try active.prepare()
            guard reply(.ready(.init(loadSeconds: seconds, encoder: active.encoderName))) else { break serve }
        } catch {
            guard reply(.failure(error.localizedDescription)) else { break serve }
        }
    case .transcribe(let samples):
        guard let active = engine else {
            guard reply(.failure("The speech model isn't loaded")) else { break serve }
            continue
        }
        do {
            let r = try active.transcribe(samples)
            guard reply(.transcription(.init(text: r.text, audioSeconds: r.audioSeconds, transcribeSeconds: r.transcribeSeconds,
                                             chunkCount: r.chunkCount, transcribedAudioSeconds: r.transcribedAudioSeconds))) else { break serve }
        } catch {
            guard reply(.failure(error.localizedDescription)) else { break serve }
        }
    case .shutdown:
        break serve
    case .ready, .transcription, .failure:
        guard reply(.failure("Unexpected message")) else { break serve }
    }
}
engine?.unload()
log.notice("helper exiting, footprint \(ResourceUsage.footprintMB, format: .fixed(precision: 0), privacy: .public) MB")
exit(0)
