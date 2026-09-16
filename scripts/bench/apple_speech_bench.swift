import Foundation
import AVFoundation
import Speech

func now() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e9 }

func transcribe(_ path: String, locale: Locale) async throws -> (String, Double) {
    let t = now()
    let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [])
    let analyzer = SpeechAnalyzer(modules: [transcriber])
    let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
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
    let text = try await collector.value
    return (text.trimmingCharacters(in: .whitespaces), now() - t)
}

let locale = Locale(identifier: CommandLine.arguments[1])
let files = Array(CommandLine.arguments[2...])
let sem = DispatchSemaphore(value: 0)
Task {
    do {
        let (_, first) = try await transcribe(files[0], locale: locale)
        print(String(format: "apple SpeechTranscriber locale=%@ first_run=%.3fs", locale.identifier, first))
        for f in files {
            let (text, dt) = try await transcribe(f, locale: locale)
            let dur = try AVAudioFile(forReading: URL(fileURLWithPath: f)).duration
            print(String(format: "  %-10@ audio=%5.2fs stt=%.3fs  %@", ((f as NSString).lastPathComponent as NSString).deletingPathExtension, dur, dt, text))
        }
    } catch { print("error:", error) }
    var ru = rusage(); getrusage(RUSAGE_SELF, &ru)
    print(String(format: "  peak_rss=%.0fMB (in-process only; model runs in system daemon)", Double(ru.ru_maxrss) / 1_048_576))
    sem.signal()
}
sem.wait()
extension AVAudioFile { var duration: Double { Double(length) / fileFormat.sampleRate } }
