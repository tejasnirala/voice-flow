import Foundation

/// Level analysis of a finished recording (16 kHz mono Float32) and the keep/discard decision.
///
/// Thresholds were calibrated on the owner's 50 benchmark recordings (MacBook mic, 2026-09-17): room noise
/// floor −55…−64 dBFS (10th percentile of 20 ms frames); speech −32…−40 dBFS (90th percentile); the shortest
/// phrase had 0.76 s of frames above −40 dBFS. See docs/PERFORMANCE.md §4.
public struct RecordingAnalysis: Equatable, Sendable {
    public var durationSeconds: Double
    /// Loudest 20 ms frame (RMS), in dBFS.
    public var peakFrameDBFS: Double
    /// Total duration of 20 ms frames louder than `RecordingGate.speechThresholdDBFS`.
    public var speechSeconds: Double
    /// Digital silence (exact zeros) at the start: the time the input device took to deliver real audio.
    public var leadingSilenceSeconds: Double
}

public enum RecordingGate {
    public enum Verdict: Equatable, Sendable {
        case keep
        /// Shorter than `minimumDurationSeconds` (an accidental tap).
        case tooShort
        /// No stretch of speech-level audio.
        case silent
    }

    public static let minimumDurationSeconds = 0.3
    public static let frameSeconds = 0.02
    /// ~10 dB above the loudest measured room noise floor, ~5–15 dB below measured speech.
    public static let speechThresholdDBFS = -45.0
    /// Enough to cover a short word; longer than a key click or a single transient.
    public static let minimumSpeechSeconds = 0.15

    public static func analyze(_ samples: [Float], sampleRate: Double) -> RecordingAnalysis {
        let duration = Double(samples.count) / sampleRate
        let frameLength = max(1, Int(sampleRate * frameSeconds))
        var peak = -Double.infinity
        var speechFrames = 0
        var start = 0
        while start < samples.count {
            let end = min(start + frameLength, samples.count)
            var sum: Float = 0
            for i in start..<end { sum += samples[i] * samples[i] }
            let rms = (sum / Float(end - start)).squareRoot()
            let db = 20 * log10(Double(max(rms, 1e-10)))
            peak = max(peak, db)
            if db > speechThresholdDBFS, end - start == frameLength { speechFrames += 1 }
            start = end
        }
        let leadingZeros = samples.firstIndex { $0 != 0 } ?? samples.count
        return RecordingAnalysis(
            durationSeconds: duration,
            peakFrameDBFS: samples.isEmpty ? -.infinity : peak,
            speechSeconds: Double(speechFrames) * frameSeconds,
            leadingSilenceSeconds: Double(leadingZeros) / sampleRate
        )
    }

    public static func verdict(for analysis: RecordingAnalysis) -> Verdict {
        if analysis.durationSeconds < minimumDurationSeconds { return .tooShort }
        if analysis.speechSeconds < minimumSpeechSeconds { return .silent }
        return .keep
    }
}
