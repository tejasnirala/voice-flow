import Foundation
import Testing
@testable import VoiceFlowCore

@Suite struct SpeechSegmenterTests {
    let rate = 16_000.0

    func tone(_ seconds: Double, dbfs: Double) -> [Float] {
        let amplitude = Float(pow(10, dbfs / 20) * 2.0.squareRoot())
        return (0..<Int(seconds * rate)).map { amplitude * Float(sin(2 * Double.pi * 220 * Double($0) / rate)) }
    }
    func speech(_ s: Double) -> [Float] { tone(s, dbfs: -30) }
    func pause(_ s: Double) -> [Float] { tone(s, dbfs: -60) }
    func seconds(_ chunk: [Range<Int>]) -> Double { Double(chunk.reduce(0) { $0 + $1.count }) / rate }

    @Test func shortAudioIsOneUntouchedChunk() {
        let samples = pause(3) + speech(5) + pause(10)
        let chunks = SpeechSegmenter.chunks(for: samples, sampleRate: rate)
        #expect(chunks == [[0..<samples.count]])
    }

    @Test func longPausesAreRemovedAndSpeechIsKept() {
        // 4 × 8 s of speech separated by 6 s pauses: 50 s total, 32 s of speech.
        var samples = pause(1)
        for _ in 0..<4 { samples += speech(8) + pause(6) }
        let chunks = SpeechSegmenter.chunks(for: samples, sampleRate: rate)
        #expect(chunks.count == 2)
        for chunk in chunks { #expect(seconds(chunk) <= 29) }
        // Each speech region keeps ≤ 0.3 s of padding on each side: total ≈ 32 + 8 × 0.3 s.
        let total = chunks.reduce(0.0) { $0 + seconds($1) }
        #expect(total > 32 && total < 32 + 8 * 0.3 + 0.1)
    }

    @Test func shortGapsStayInsideARegion() {
        let samples = speech(10) + pause(0.3) + speech(10) + pause(15) + speech(10)
        let chunks = SpeechSegmenter.chunks(for: samples, sampleRate: rate)
        // The 0.3 s gap is bridged (one 20.3 s region + padding); the final 10 s doesn't fit, so it's a second chunk.
        #expect(chunks.count == 2)
        #expect(chunks[0].count == 1)
        #expect(abs(seconds(chunks[0]) - 20.6) < 0.1)
    }

    @Test func continuousSpeechLongerThanAChunkIsSplit() {
        let samples = pause(1) + speech(60) + pause(1)
        let chunks = SpeechSegmenter.chunks(for: samples, sampleRate: rate)
        #expect(chunks.count == 3)
        for chunk in chunks { #expect(seconds(chunk) <= 29) }
        #expect(abs(chunks.reduce(0.0) { $0 + seconds($1) } - 60.6) < 0.1)
    }

    @Test func splitsAtTheQuietestPoint() {
        // 20 s speech, a 0.4 s dip (bridged, so still one region), then 20 s more: the cut should land in the dip.
        let samples = speech(20) + tone(0.4, dbfs: -50) + speech(20)
        let chunks = SpeechSegmenter.chunks(for: samples, sampleRate: rate)
        let cut = Double(chunks[0].last!.upperBound) / rate
        #expect(cut > 20 && cut < 20.4)
    }

    @Test func chunkEndsAtTheLongestPause() {
        // Five 6 s utterances (6.6 s each with padding = 33 s) need 2 chunks. A greedy packer would cut after the 4th
        // utterance (26.4 s); the cut should instead use the 5 s pause after the 3rd (19.8 s, past 60% of 29 s).
        let samples = speech(6) + pause(1) + speech(6) + pause(1) + speech(6) + pause(5) + speech(6) + pause(1) + speech(6)
        let chunks = SpeechSegmenter.chunks(for: samples, sampleRate: rate)
        #expect(chunks.count == 2)
        #expect(chunks[0].count == 3)
        #expect(chunks[1].count == 2)
    }

    @Test func silentLongAudioHasNoChunks() {
        #expect(SpeechSegmenter.chunks(for: pause(40), sampleRate: rate).isEmpty)
    }

    @Test func chunkAudioConcatenatesRanges() {
        let samples: [Float] = (0..<10).map(Float.init)
        #expect(SpeechSegmenter.audio(for: [0..<2, 5..<7], in: samples) == [0, 1, 5, 6])
    }
}
