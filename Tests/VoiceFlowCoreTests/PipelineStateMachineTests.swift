import Testing
@testable import VoiceFlowCore

@Suite struct PipelineStateMachineTests {
    static let failure = PipelineFailure(stage: .transcription, message: "model missing")
    static let hotkeyFailure = PipelineFailure(stage: .hotkey, message: "⌥Space is in use")
    static let retryableFailure = PipelineFailure(stage: .transcription, message: "model missing", recovery: .retryTranscription)

    static let allStates: [PipelineState] = [.idle, .recording, .transcribing, .processing, .inserting, .error(failure), .error(retryableFailure)]
    static let allEvents: [PipelineEvent] = [
        .hotkeyPressed, .hotkeyReleased, .cancelRequested, .recordingLimitReached, .recordingDiscarded,
        .transcriptionSucceeded(needsProcessing: true), .transcriptionSucceeded(needsProcessing: false),
        .transcriptionEmpty, .processingSucceeded, .processingFellBackToTranscript, .insertionFinished,
        .failed(failure), .failed(hotkeyFailure), .errorDismissed, .retryTranscriptionRequested,
    ]

    /// The complete transition table. Any (state, event) pair not listed must be rejected.
    static let expected: [(PipelineState, PipelineEvent, PipelineState)] = [
        (.idle, .hotkeyPressed, .recording),
        (.idle, .failed(hotkeyFailure), .error(hotkeyFailure)),
        (.recording, .hotkeyReleased, .transcribing),
        (.recording, .recordingLimitReached, .transcribing),
        (.recording, .recordingDiscarded, .idle),
        (.recording, .cancelRequested, .idle),
        (.recording, .failed(failure), .error(failure)),
        (.recording, .failed(hotkeyFailure), .error(hotkeyFailure)),
        (.transcribing, .transcriptionSucceeded(needsProcessing: true), .processing),
        (.transcribing, .transcriptionSucceeded(needsProcessing: false), .inserting),
        (.transcribing, .transcriptionEmpty, .idle),
        (.transcribing, .cancelRequested, .idle),
        (.transcribing, .failed(failure), .error(failure)),
        (.transcribing, .failed(hotkeyFailure), .error(hotkeyFailure)),
        (.processing, .processingSucceeded, .inserting),
        (.processing, .processingFellBackToTranscript, .inserting),
        (.processing, .cancelRequested, .idle),
        (.processing, .failed(failure), .error(failure)),
        (.processing, .failed(hotkeyFailure), .error(hotkeyFailure)),
        (.inserting, .insertionFinished, .idle),
        (.inserting, .failed(failure), .error(failure)),
        (.inserting, .failed(hotkeyFailure), .error(hotkeyFailure)),
        (.error(failure), .hotkeyPressed, .recording),
        (.error(failure), .errorDismissed, .idle),
        (.error(retryableFailure), .hotkeyPressed, .recording),
        (.error(retryableFailure), .errorDismissed, .idle),
        (.error(retryableFailure), .retryTranscriptionRequested, .transcribing),
    ]

    @Test func transitionTableIsExhaustive() {
        for state in Self.allStates {
            for event in Self.allEvents {
                let want = Self.expected.first { $0.0 == state && $0.1 == event }?.2
                let got = PipelineStateMachine.transition(from: state, on: event)
                #expect(got == want, "\(state) + \(event): expected \(String(describing: want)), got \(String(describing: got))")
            }
        }
    }

    @Test func fastModeHappyPath() {
        var m = PipelineStateMachine()
        #expect(m.handle(.hotkeyPressed) == .recording)
        #expect(m.handle(.hotkeyReleased) == .transcribing)
        #expect(m.handle(.transcriptionSucceeded(needsProcessing: false)) == .inserting)
        #expect(m.handle(.insertionFinished) == .idle)
    }

    @Test func smartModeFailureStillInsertsTranscript() {
        var m = PipelineStateMachine()
        m.handle(.hotkeyPressed); m.handle(.hotkeyReleased)
        #expect(m.handle(.transcriptionSucceeded(needsProcessing: true)) == .processing)
        #expect(m.handle(.processingFellBackToTranscript) == .inserting)
    }

    @Test func duplicatePressesAndStrayReleasesAreIgnored() {
        var m = PipelineStateMachine()
        #expect(m.handle(.hotkeyReleased) == nil)
        #expect(m.state == .idle)
        m.handle(.hotkeyPressed)
        #expect(m.handle(.hotkeyPressed) == nil)
        #expect(m.state == .recording)
    }

    @Test func cancelThenLateResultIsIgnored() {
        var m = PipelineStateMachine()
        m.handle(.hotkeyPressed); m.handle(.hotkeyReleased)
        #expect(m.handle(.cancelRequested) == .idle)
        #expect(m.handle(.transcriptionSucceeded(needsProcessing: false)) == nil)
        #expect(m.state == .idle)
    }

    @Test func insertionCannotBeCancelled() {
        var m = PipelineStateMachine()
        m.handle(.hotkeyPressed); m.handle(.hotkeyReleased); m.handle(.transcriptionSucceeded(needsProcessing: false))
        #expect(m.handle(.cancelRequested) == nil)
        #expect(m.state == .inserting)
    }

    @Test func errorRecoversByRetryOrDismiss() {
        var m = PipelineStateMachine()
        m.handle(.hotkeyPressed)
        #expect(m.handle(.failed(Self.failure)) == .error(Self.failure))
        #expect(m.handle(.hotkeyPressed) == .recording)
        m.handle(.failed(Self.failure))
        #expect(m.handle(.errorDismissed) == .idle)
    }

    /// Microphone permission denied: recording fails with a recovery that opens System Settings; the next press works
    /// once access is granted, and nothing is left half-recorded.
    @Test func microphoneDeniedRecoversAfterAccessIsGranted() {
        var m = PipelineStateMachine()
        m.handle(.hotkeyPressed)
        let denied = PipelineFailure(stage: .recording, message: "Microphone access is off for VoiceFlow", recovery: .openMicrophoneSettings)
        #expect(m.handle(.failed(denied)) == .error(denied))
        #expect(m.handle(.hotkeyReleased) == nil)
        #expect(m.handle(.hotkeyPressed) == .recording)
    }

    /// Paste failure (no Accessibility): an insertion-stage error; dismissing it returns to idle.
    @Test func pasteFailureIsReportedAndDismissible() {
        var m = PipelineStateMachine()
        m.handle(.hotkeyPressed)
        m.handle(.hotkeyReleased)
        m.handle(.transcriptionSucceeded(needsProcessing: false))
        let paste = PipelineFailure(stage: .insertion, message: "Copied to the clipboard", recovery: .openAccessibilitySettings)
        #expect(m.handle(.failed(paste)) == .error(paste))
        #expect(m.handle(.errorDismissed) == .idle)
    }

    @Test func nonHotkeyFailureWhileIdleIsIgnored() {
        var m = PipelineStateMachine()
        #expect(m.handle(.failed(Self.failure)) == nil)
        #expect(m.handle(.failed(Self.hotkeyFailure)) == .error(Self.hotkeyFailure))
    }
}
