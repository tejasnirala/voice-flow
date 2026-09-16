import Foundation
import AVFoundation
import whisper

func now() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e9 }
func loadPCM(_ path: String) -> [Float] {
    let file = try! AVAudioFile(forReading: URL(fileURLWithPath: path), commonFormat: .pcmFormatFloat32, interleaved: false)
    let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
    try! file.read(into: buf)
    precondition(file.processingFormat.sampleRate == 16000)
    return Array(UnsafeBufferPointer(start: buf.floatChannelData![0], count: Int(buf.frameLength)))
}

let args = CommandLine.arguments
let modelPath = args[1], useGPU = args[2] == "gpu", files = Array(args[3...])
whisper_log_set({ _, _, _ in }, nil)

var cp = whisper_context_default_params()
cp.use_gpu = useGPU
cp.flash_attn = useGPU
var t0 = now()
guard let ctx = whisper_init_from_file_with_params(modelPath, cp) else { fatalError("load failed") }
let loadS = now() - t0

func transcribe(_ pcm: [Float]) -> (String, Double) {
    var p = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
    p.n_threads = 4
    p.print_progress = false; p.print_realtime = false; p.print_timestamps = false; p.print_special = false
    p.no_timestamps = true
    p.single_segment = false
    let lang = strdup("en"); defer { free(lang) }
    p.language = UnsafePointer(lang)
    let t = now()
    let rc = pcm.withUnsafeBufferPointer { whisper_full(ctx, p, $0.baseAddress, Int32($0.count)) }
    let dt = now() - t
    precondition(rc == 0)
    var out = ""
    for i in 0..<whisper_full_n_segments(ctx) { out += String(cString: whisper_full_get_segment_text(ctx, i)) }
    return (out.trimmingCharacters(in: .whitespaces), dt)
}

// Warm-up on the first clip (first run pays Metal pipeline compilation).
t0 = now(); _ = transcribe(loadPCM(files[0])); let warmupS = now() - t0
print(String(format: "model=%@ backend=%@ load=%.3fs first_run=%.3fs", (modelPath as NSString).lastPathComponent, useGPU ? "metal" : "cpu", loadS, warmupS))
for f in files {
    let pcm = loadPCM(f)
    let (text, dt) = transcribe(pcm)
    print(String(format: "  %-10@ audio=%5.2fs stt=%.3fs  %@", ((f as NSString).lastPathComponent as NSString).deletingPathExtension, Double(pcm.count)/16000, dt, text))
}
var ru = rusage(); getrusage(RUSAGE_SELF, &ru)
print(String(format: "  peak_rss=%.0fMB", Double(ru.ru_maxrss) / 1_048_576))
whisper_free(ctx)
