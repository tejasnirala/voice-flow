import Foundation
import Testing
@testable import VoiceFlowCore

@Suite struct SpeechHelperProtocolTests {
    /// Decodes from an in-memory stream.
    func roundTrip(_ messages: [SpeechHelperMessage]) throws -> [SpeechHelperMessage] {
        var stream = Data()
        for m in messages { stream.append(try SpeechHelperWire.encode(m)) }
        var offset = stream.startIndex
        let read: (Int) throws -> Data = { n in
            let end = min(offset + n, stream.endIndex)
            defer { offset = end }
            return stream[offset..<end]
        }
        var out: [SpeechHelperMessage] = []
        while offset < stream.endIndex { out.append(try SpeechHelperWire.decode(read: read)) }
        return out
    }

    @Test func roundTripsEveryMessageKind() throws {
        let messages: [SpeechHelperMessage] = [
            .prepare(.init(modelPath: "/m/ggml-medium.en-q8_0.bin", modelFileName: "ggml-medium.en-q8_0.bin", language: "en",
                           prompt: "Next.js, PostgreSQL")),
            .prepare(.init(modelPath: "/m/x.bin", modelFileName: "x.bin", language: "en", prompt: nil)),
            .transcribe([0, 0.5, -1, 1e-6, .pi]),
            .transcribe([]),
            .ready(.init(loadSeconds: 0.31, encoder: "Core ML")),
            .transcription(.init(text: "Run npm run dev — ✓", audioSeconds: 5.2, transcribeSeconds: 0.61, chunkCount: 1,
                                 transcribedAudioSeconds: 5.2)),
            .failure("model missing"),
            .shutdown,
        ]
        #expect(try roundTrip(messages) == messages)
    }

    @Test func largeAudioSurvivesFraming() throws {
        let samples = (0..<(16_000 * 60)).map { Float(sin(Double($0) / 7)) }
        #expect(try roundTrip([.transcribe(samples)]) == [.transcribe(samples)])
    }

    @Test func truncatedStreamReportsEndOfStream() throws {
        let frame = try SpeechHelperWire.encode(.transcribe([1, 2, 3]))
        let cut = frame.prefix(frame.count - 2)
        var offset = cut.startIndex
        #expect(throws: SpeechHelperWire.WireError.endOfStream) {
            _ = try SpeechHelperWire.decode(read: { n in
                let end = min(offset + n, cut.endIndex); defer { offset = end }; return cut[offset..<end]
            })
        }
    }

    @Test func emptyStreamIsEndOfStream() {
        #expect(throws: SpeechHelperWire.WireError.endOfStream) {
            _ = try SpeechHelperWire.decode(read: { _ in Data() })
        }
    }

    @Test func rejectsUnknownKind() {
        var frame = Data([99, 2, 0, 0, 0]); frame.append(Data("{}".utf8)); frame.append(Data([0, 0, 0, 0]))
        var offset = frame.startIndex
        #expect(throws: SpeechHelperWire.WireError.unknownKind(99)) {
            _ = try SpeechHelperWire.decode(read: { n in
                let end = min(offset + n, frame.endIndex); defer { offset = end }; return frame[offset..<end]
            })
        }
    }
}
