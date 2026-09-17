/// A failure shown to the user. `message` must never contain transcript text.
public struct PipelineFailure: Equatable, Sendable {
    public enum Stage: String, Sendable { case hotkey, recording, transcription, processing, insertion }
    /// Something the UI can offer so the user can fix the problem.
    public enum Recovery: Equatable, Sendable { case openMicrophoneSettings }

    public var stage: Stage
    public var message: String
    public var recovery: Recovery?

    public init(stage: Stage, message: String, recovery: Recovery? = nil) {
        self.stage = stage
        self.message = message
        self.recovery = recovery
    }
}

public enum PipelineState: Equatable, Sendable {
    case idle
    case recording
    case transcribing
    case processing
    case inserting
    case error(PipelineFailure)

    /// States in which work for a dictation is in flight.
    public var isActive: Bool {
        switch self {
        case .recording, .transcribing, .processing, .inserting: true
        case .idle, .error: false
        }
    }
}

public enum PipelineEvent: Equatable, Sendable {
    case hotkeyPressed
    case hotkeyReleased
    /// Esc while recording, or an explicit cancel from the UI.
    case cancelRequested
    /// Recording hit the max duration: treated like a release so the speech isn't lost.
    case recordingLimitReached
    /// Recording was too short or silent: nothing to transcribe.
    case recordingDiscarded
    case transcriptionSucceeded(needsProcessing: Bool)
    /// STT found no speech.
    case transcriptionEmpty
    case processingSucceeded
    /// Smart Mode failed: insert the raw transcript instead of losing it.
    case processingFellBackToTranscript
    case insertionFinished
    case failed(PipelineFailure)
    case errorDismissed
}

/// The explicit, deterministic dictation state machine. Side effects (start the recorder, run STT, …) are
/// performed by the app coordinator in response to accepted transitions. This type only decides what's legal.
public struct PipelineStateMachine: Sendable {
    public private(set) var state: PipelineState = .idle

    public init() {}

    /// Applies `event`. Returns the new state, or `nil` if the event isn't valid in the current state
    /// (duplicates, stray releases, late results after a cancel); the state is then unchanged.
    @discardableResult
    public mutating func handle(_ event: PipelineEvent) -> PipelineState? {
        guard let next = Self.transition(from: state, on: event) else { return nil }
        state = next
        return next
    }

    public static func transition(from state: PipelineState, on event: PipelineEvent) -> PipelineState? {
        switch (state, event) {
        // Start. Retrying from an error is allowed so the user is never stuck.
        case (.idle, .hotkeyPressed), (.error, .hotkeyPressed):
            return .recording

        case (.recording, .hotkeyReleased), (.recording, .recordingLimitReached):
            return .transcribing
        case (.recording, .recordingDiscarded):
            return .idle

        case (.transcribing, .transcriptionSucceeded(let needsProcessing)):
            return needsProcessing ? .processing : .inserting
        case (.transcribing, .transcriptionEmpty):
            return .idle

        case (.processing, .processingSucceeded), (.processing, .processingFellBackToTranscript):
            return .inserting

        case (.inserting, .insertionFinished):
            return .idle

        // Cancel before insertion starts. Insertion is short and not interruptible, to avoid half-pasted text.
        case (.recording, .cancelRequested), (.transcribing, .cancelRequested), (.processing, .cancelRequested):
            return .idle

        case (let s, .failed(let failure)) where s.isActive:
            return .error(failure)
        // A hotkey failure (e.g. the combination is taken) can surface while idle.
        case (.idle, .failed(let failure)) where failure.stage == .hotkey:
            return .error(failure)

        case (.error, .errorDismissed):
            return .idle

        default:
            return nil
        }
    }
}
