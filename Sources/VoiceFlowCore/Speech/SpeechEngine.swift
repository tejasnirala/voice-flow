/// Result of transcribing one recording. `text` is user content: never log it.
public struct TranscriptionResult: Equatable, Sendable {
    public var text: String
    public var audioSeconds: Double
    public var transcribeSeconds: Double
    /// Whether the model had to be loaded for this request.
    public var coldStart: Bool
    /// Time spent loading the model within this request (0 when warm).
    public var loadSeconds: Double
    /// Time spent waiting for a load already in progress (started when recording began).
    public var waitedForModelSeconds: Double
    /// What `TranscriptGuard` changed or flagged.
    public var guardFlags: Set<TranscriptGuard.Flag>
    /// Chunks transcribed (1 for audio up to `SpeechSegmenter` max chunk length).
    public var chunkCount: Int = 1
    /// Seconds of audio actually sent to the model after removing long silences.
    public var transcribedAudioSeconds: Double = 0

    public init(text: String, audioSeconds: Double, transcribeSeconds: Double, coldStart: Bool, loadSeconds: Double,
                waitedForModelSeconds: Double = 0, guardFlags: Set<TranscriptGuard.Flag> = []) {
        self.waitedForModelSeconds = waitedForModelSeconds
        self.text = text
        self.audioSeconds = audioSeconds
        self.transcribeSeconds = transcribeSeconds
        self.coldStart = coldStart
        self.loadSeconds = loadSeconds
        self.guardFlags = guardFlags
    }
}

/// The replaceable STT boundary (spec rule 15). Implementations must be safe to call from any thread and
/// serialize access to their model internally.
public protocol SpeechEngine: AnyObject, Sendable {
    /// Loads the model if needed (e.g. started when recording begins, so it's ready at release).
    func prepare() throws
    /// Transcribes 16 kHz mono Float32 samples.
    func transcribe(_ samples: [Float]) throws -> TranscriptionResult
    /// Frees the model. Must be called before process exit for Metal-backed engines.
    func unload()
    var isLoaded: Bool { get }
}
