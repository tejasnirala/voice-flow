import Foundation

/// Splits long recordings into chunks Whisper handles reliably.
///
/// Whisper decodes in 30 s windows. On long dictations with thinking pauses, it measurably skips speech and invents
/// repeated text (owner dictation: 89.7 s audio, 54.6 s speech → 69 words with a hallucinated loop; long-form benchmark
/// WER 22.7%). The segmenter removes long silences and packs the speech into chunks of at most `maxChunkSeconds`
/// that are transcribed independently.
///
/// Audio no longer than `maxChunkSeconds` (just under Whisper's 30 s window) is returned as one untouched chunk: the
/// validated short-dictation path. Chunk boundaries prefer the longest pause, so they fall between sentences.
public enum SpeechSegmenter {
    public struct Configuration: Sendable, Equatable {
        public var maxChunkSeconds = 29.0
        /// Audio kept around each speech region (real room audio, so word onsets and tails aren't clipped).
        public var paddingSeconds = 0.3
        /// Silences shorter than this stay inside a speech region.
        public var bridgeGapSeconds = 0.5
        public var speechThresholdDBFS = RecordingGate.speechThresholdDBFS
        public var frameSeconds = RecordingGate.frameSeconds
        /// A chunk needs at least this much speech to be transcribed.
        public var minimumSpeechSeconds = RecordingGate.minimumSpeechSeconds

        public init() {}
    }

    /// Each chunk is a list of sample ranges to concatenate, in order.
    public static func chunks(for samples: [Float], sampleRate: Double,
                              configuration c: Configuration = Configuration()) -> [[Range<Int>]] {
        guard !samples.isEmpty else { return [] }
        let maxChunk = Int(c.maxChunkSeconds * sampleRate)
        if samples.count <= maxChunk { return [[0..<samples.count]] }

        let frame = max(1, Int(sampleRate * c.frameSeconds))
        let levels = frameLevels(samples, frame: frame)
        let speech = levels.map { $0 > c.speechThresholdDBFS }

        // 1. Speech regions in frames, bridging short gaps.
        var regions: [Range<Int>] = []
        let bridge = Int(c.bridgeGapSeconds / c.frameSeconds)
        var i = 0
        while i < speech.count {
            guard speech[i] else { i += 1; continue }
            var end = i + 1
            var lastSpeech = i
            while end < speech.count, end - lastSpeech <= bridge {
                if speech[end] { lastSpeech = end }
                end += 1
            }
            regions.append(i..<(lastSpeech + 1))
            i = lastSpeech + 1
        }
        let minFrames = Int((c.minimumSpeechSeconds / c.frameSeconds).rounded(.up))
        guard regions.reduce(0, { $0 + $1.count }) >= minFrames else { return [] }

        // 2. Pad regions (in samples) and merge overlaps.
        let pad = Int(c.paddingSeconds * sampleRate)
        var padded: [Range<Int>] = []
        for r in regions {
            let range = max(0, r.lowerBound * frame - pad)..<min(samples.count, r.upperBound * frame + pad)
            if let last = padded.last, range.lowerBound <= last.upperBound {
                padded[padded.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else {
                padded.append(range)
            }
        }

        // 3. Split any region longer than a chunk at its quietest frame between 60% and 100% of the chunk length.
        var pieces: [Range<Int>] = []
        for var r in padded {
            while r.count > maxChunk {
                let searchStart = r.lowerBound + maxChunk * 3 / 5
                let searchEnd = r.lowerBound + maxChunk
                let firstFrame = searchStart / frame, lastFrame = min(levels.count - 1, searchEnd / frame - 1)
                var cut = searchEnd
                if firstFrame <= lastFrame {
                    // Quietest frame; on ties the latest one, so chunks stay as long as allowed (fewer Whisper calls).
                    var quietest = firstFrame
                    for f in firstFrame...lastFrame where levels[f] <= levels[quietest] { quietest = f }
                    cut = quietest * frame + frame / 2
                }
                pieces.append(r.lowerBound..<cut)
                r = cut..<r.upperBound
            }
            pieces.append(r)
        }

        // 4. Pack pieces into chunks of at most maxChunk samples. When a chunk must end, end it at the longest pause
        //    among boundaries in its last 40% (splits inside continuous speech have no pause and are least preferred).
        var result: [[Range<Int>]] = []
        var startIndex = 0
        while startIndex < pieces.count {
            var length = 0
            var endIndex = startIndex
            while endIndex < pieces.count, length + pieces[endIndex].count <= maxChunk || endIndex == startIndex {
                length += pieces[endIndex].count
                endIndex += 1
            }
            if endIndex < pieces.count {
                var best = endIndex
                var bestGap = -1
                var prefix = 0
                for boundary in (startIndex + 1)...endIndex {
                    prefix += pieces[boundary - 1].count
                    guard prefix >= maxChunk * 3 / 5 else { continue }
                    let gap = pieces[boundary].lowerBound - pieces[boundary - 1].upperBound
                    if gap > bestGap { bestGap = gap; best = boundary }
                }
                endIndex = best
            }
            result.append(Array(pieces[startIndex..<endIndex]))
            startIndex = endIndex
        }
        return result
    }

    /// Concatenates a chunk's ranges into one buffer.
    public static func audio(for chunk: [Range<Int>], in samples: [Float]) -> [Float] {
        var out: [Float] = []
        out.reserveCapacity(chunk.reduce(0) { $0 + $1.count })
        for range in chunk { out.append(contentsOf: samples[range]) }
        return out
    }

    static func frameLevels(_ samples: [Float], frame: Int) -> [Double] {
        stride(from: 0, to: samples.count, by: frame).map { start in
            let end = min(start + frame, samples.count)
            var sum: Float = 0
            for i in start..<end { sum += samples[i] * samples[i] }
            return 20 * log10(Double(max((sum / Float(end - start)).squareRoot(), 1e-10)))
        }
    }
}
