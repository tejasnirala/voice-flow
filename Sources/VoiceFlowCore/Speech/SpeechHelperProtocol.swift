import Foundation

/// Audio format every STT engine consumes.
public enum STTAudio {
    public static let sampleRate = 16_000.0
}

/// Messages between the app and the `voiceflow-stt` helper process, which is the only process that loads whisper.cpp.
/// When the helper exits, all model memory (including allocations whisper.cpp never frees) returns to the system.
public enum SpeechHelperMessage: Equatable, Sendable {
    public struct Prepare: Codable, Equatable, Sendable {
        public var modelPath: String
        public var modelFileName: String
        public var language: String
        public var prompt: String?

        public init(modelPath: String, modelFileName: String, language: String, prompt: String?) {
            self.modelPath = modelPath
            self.modelFileName = modelFileName
            self.language = language
            self.prompt = prompt
        }
    }

    public struct Ready: Codable, Equatable, Sendable {
        public var loadSeconds: Double
        public var encoder: String

        public init(loadSeconds: Double, encoder: String) {
            self.loadSeconds = loadSeconds
            self.encoder = encoder
        }
    }

    public struct Transcription: Codable, Equatable, Sendable {
        public var text: String
        public var audioSeconds: Double
        public var transcribeSeconds: Double
        public var chunkCount: Int
        public var transcribedAudioSeconds: Double

        public init(text: String, audioSeconds: Double, transcribeSeconds: Double, chunkCount: Int, transcribedAudioSeconds: Double) {
            self.text = text
            self.audioSeconds = audioSeconds
            self.transcribeSeconds = transcribeSeconds
            self.chunkCount = chunkCount
            self.transcribedAudioSeconds = transcribedAudioSeconds
        }
    }

    /// Which loaded model transcribes, in which language, with which vocabulary prompt.
    public struct Transcribe: Codable, Equatable, Sendable {
        public var modelPath: String
        public var modelFileName: String
        public var language: String
        public var prompt: String?

        public init(modelPath: String, modelFileName: String, language: String, prompt: String?) {
            self.modelPath = modelPath
            self.modelFileName = modelFileName
            self.language = language
            self.prompt = prompt
        }
    }

    /// Detect the spoken language with a (multilingual) model, among `candidates` (Whisper codes).
    public struct Detect: Codable, Equatable, Sendable {
        public var modelPath: String
        public var modelFileName: String
        public var candidates: [String]

        public init(modelPath: String, modelFileName: String, candidates: [String]) {
            self.modelPath = modelPath
            self.modelFileName = modelFileName
            self.candidates = candidates
        }
    }

    public struct Detection: Codable, Equatable, Sendable {
        /// Probability per candidate code.
        public var probabilities: [String: Double]
        public var seconds: Double

        public init(probabilities: [String: Double], seconds: Double) {
            self.probabilities = probabilities
            self.seconds = seconds
        }
    }

    /// App → helper: load a model; several can be loaded at once (reply `.ready` or `.failure`).
    case prepare(Prepare)
    /// App → helper: transcribe 16 kHz mono Float32 samples (reply `.transcription` or `.failure`).
    case transcribe(Transcribe, [Float])
    /// App → helper: detect the language of 16 kHz mono Float32 samples (reply `.detection` or `.failure`).
    case detectLanguage(Detect, [Float])
    case detection(Detection)
    /// App → helper: free the model and exit.
    case shutdown
    case ready(Ready)
    case transcription(Transcription)
    case failure(String)
}

/// Binary framing: `[kind: UInt8][json length: UInt32 LE][json][payload length: UInt32 LE][payload]`.
/// JSON carries the control data; the payload carries raw little-endian Float32 audio for `.transcribe`.
public enum SpeechHelperWire {
    public enum WireError: Error, Equatable {
        case endOfStream
        case unknownKind(UInt8)
        case frameTooLarge(Int)
        case malformed
    }

    /// Upper bound per section (10 minutes of audio is 38.4 MB), protecting against a corrupt stream.
    static let maxSectionBytes = 64 << 20

    public static func encode(_ message: SpeechHelperMessage) throws -> Data {
        let encoder = JSONEncoder()
        var kind: UInt8
        var json = Data("{}".utf8)
        var payload = Data()
        switch message {
        case .prepare(let value): kind = 1; json = try encoder.encode(value)
        case .transcribe(let options, let samples):
            kind = 2
            json = try encoder.encode(options)
            payload = samples.withUnsafeBufferPointer { Data(buffer: $0) }
        case .detectLanguage(let options, let samples):
            kind = 7
            json = try encoder.encode(options)
            payload = samples.withUnsafeBufferPointer { Data(buffer: $0) }
        case .detection(let value): kind = 8; json = try encoder.encode(value)
        case .shutdown: kind = 3
        case .ready(let value): kind = 4; json = try encoder.encode(value)
        case .transcription(let value): kind = 5; json = try encoder.encode(value)
        case .failure(let message): kind = 6; json = try encoder.encode(["message": message])
        }
        var frame = Data([kind])
        append(UInt32(json.count), to: &frame)
        frame.append(json)
        append(UInt32(payload.count), to: &frame)
        frame.append(payload)
        return frame
    }

    /// Reads one message using `read(n)`, which must return exactly `n` bytes, or fewer only at end of stream.
    public static func decode(read: (Int) throws -> Data) throws -> SpeechHelperMessage {
        let kindData = try read(1)
        guard kindData.count == 1 else { throw WireError.endOfStream }
        let json = try section(read)
        let payload = try section(read)
        let decoder = JSONDecoder()
        switch kindData[kindData.startIndex] {
        case 1: return .prepare(try decoder.decode(SpeechHelperMessage.Prepare.self, from: json))
        case 2, 7:
            guard payload.count % MemoryLayout<Float>.size == 0 else { throw WireError.malformed }
            let samples = payload.withUnsafeBytes { raw in Array(raw.bindMemory(to: Float.self)) }
            if kindData[kindData.startIndex] == 2 {
                return .transcribe(try decoder.decode(SpeechHelperMessage.Transcribe.self, from: json), samples)
            }
            return .detectLanguage(try decoder.decode(SpeechHelperMessage.Detect.self, from: json), samples)
        case 8: return .detection(try decoder.decode(SpeechHelperMessage.Detection.self, from: json))
        case 3: return .shutdown
        case 4: return .ready(try decoder.decode(SpeechHelperMessage.Ready.self, from: json))
        case 5: return .transcription(try decoder.decode(SpeechHelperMessage.Transcription.self, from: json))
        case 6:
            let body = try decoder.decode([String: String].self, from: json)
            return .failure(body["message"] ?? "Unknown error")
        case let other: throw WireError.unknownKind(other)
        }
    }

    private static func section(_ read: (Int) throws -> Data) throws -> Data {
        let lengthData = try read(4)
        guard lengthData.count == 4 else { throw WireError.endOfStream }
        let length = Int(lengthData.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.littleEndian)
        guard length <= maxSectionBytes else { throw WireError.frameTooLarge(length) }
        guard length > 0 else { return Data() }
        let data = try read(length)
        guard data.count == length else { throw WireError.endOfStream }
        return data
    }

    private static func append(_ value: UInt32, to data: inout Data) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }
}

public extension FileHandle {
    /// Reads exactly `count` bytes, blocking; returns fewer only at end of file.
    func readExactly(_ count: Int) throws -> Data {
        var data = Data()
        data.reserveCapacity(count)
        while data.count < count {
            guard let chunk = try read(upToCount: count - data.count), !chunk.isEmpty else { break }
            data.append(chunk)
        }
        return data
    }
}
