import Foundation
import Testing
@testable import VoiceFlowCore

@Suite struct RecordingGateTests {
    let rate = 16_000.0

    /// A sine tone at the given RMS level in dBFS.
    func tone(seconds: Double, dbfs: Double) -> [Float] {
        let amplitude = Float(pow(10, dbfs / 20) * 2.0.squareRoot())
        return (0..<Int(seconds * rate)).map { amplitude * Float(sin(2 * Double.pi * 220 * Double($0) / rate)) }
    }

    @Test func speechLevelRecordingIsKept() {
        let samples = tone(seconds: 0.5, dbfs: -60) + tone(seconds: 1.0, dbfs: -35) + tone(seconds: 0.5, dbfs: -60)
        let a = RecordingGate.analyze(samples, sampleRate: rate)
        #expect(abs(a.durationSeconds - 2.0) < 0.001)
        #expect(abs(a.peakFrameDBFS - -35) < 0.5)
        #expect(abs(a.speechSeconds - 1.0) < 0.05)
        #expect(RecordingGate.verdict(for: a) == .keep)
    }

    @Test func roomNoiseOnlyIsSilent() {
        let a = RecordingGate.analyze(tone(seconds: 3, dbfs: -55), sampleRate: rate)
        #expect(a.speechSeconds == 0)
        #expect(RecordingGate.verdict(for: a) == .silent)
    }

    @Test func briefClickIsSilent() {
        let samples = tone(seconds: 0.5, dbfs: -60) + tone(seconds: 0.06, dbfs: -30) + tone(seconds: 0.5, dbfs: -60)
        #expect(RecordingGate.verdict(for: RecordingGate.analyze(samples, sampleRate: rate)) == .silent)
    }

    @Test func accidentalTapIsTooShort() {
        let a = RecordingGate.analyze(tone(seconds: 0.2, dbfs: -30), sampleRate: rate)
        #expect(RecordingGate.verdict(for: a) == .tooShort)
    }

    @Test func emptyRecordingIsTooShort() {
        let a = RecordingGate.analyze([], sampleRate: rate)
        #expect(a.durationSeconds == 0)
        #expect(RecordingGate.verdict(for: a) == .tooShort)
    }

    @Test func measuresLeadingDigitalSilence() {
        let samples = [Float](repeating: 0, count: 3_200) + tone(seconds: 1, dbfs: -35)
        let a = RecordingGate.analyze(samples, sampleRate: rate)
        #expect(abs(a.leadingSilenceSeconds - 0.2) < 0.001)
    }
}
