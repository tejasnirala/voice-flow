/// Turns presses of a single modifier key (⌥) into dictation actions, Wispr Flow–style:
///
/// - **Hold** the key: recording starts at key-down and is transcribed at key-up.
/// - **Double-tap** the key: hands-free recording; the next press of the key finishes and transcribes.
/// - A **quick single tap** does nothing (the recording started at key-down is discarded).
/// - **Chords** (another key or modifier pressed together with it, e.g. ⌥←, ⌥⇧) cancel silently, so ordinary
///   shortcuts keep working.
///
/// Pure and deterministic: the caller supplies timestamps (seconds) and fires the double-tap timer.
public struct ModifierKeyGesture: Sendable {
    public enum Input: Equatable, Sendable {
        case keyDown
        case keyUp
        /// Another key or modifier was pressed while the modifier was held.
        case chord
        /// The double-tap window elapsed (scheduled via `.scheduleDoubleTapTimeout`).
        case doubleTapTimeout
    }

    public enum Action: Equatable, Sendable {
        /// Start recording (hold, first tap, or locked mode).
        case startRecording
        /// Stop recording and transcribe.
        case finishRecording
        /// Stop recording and discard it (single tap, or a chord).
        case cancelRecording
        /// Recording continues hands-free until the next press.
        case enteredHandsFree
        case scheduleDoubleTapTimeout(seconds: Double)
    }

    public enum Phase: Equatable, Sendable {
        case idle
        /// Key is down; still deciding whether this is a hold or a tap.
        case pressed(since: Double)
        /// First tap released; waiting to see whether a second tap follows.
        case awaitingSecondTap(releasedAt: Double)
        /// Second tap is down (hands-free already on); its release is ignored.
        case secondTapDown
        case handsFree
        /// Finishing press in hands-free mode is down; its release is ignored.
        case finishingPressDown
    }

    /// A press shorter than this is a tap.
    public static let tapMaxSeconds = 0.3
    /// The second tap must start within this time after the first tap's release.
    public static let doubleTapWindowSeconds = 0.4

    public private(set) var phase: Phase = .idle

    public init() {}

    public var isHandsFree: Bool {
        switch phase {
        case .secondTapDown, .handsFree: true
        default: false
        }
    }

    /// External cancel or completion (e.g. Esc, max duration, error): back to idle without further actions.
    public mutating func reset() { phase = .idle }

    public mutating func handle(_ input: Input, at time: Double) -> [Action] {
        switch (phase, input) {
        case (.idle, .keyDown):
            phase = .pressed(since: time)
            return [.startRecording]

        case (.pressed(let since), .keyUp):
            if time - since >= Self.tapMaxSeconds {
                phase = .idle
                return [.finishRecording]
            }
            phase = .awaitingSecondTap(releasedAt: time)
            return [.scheduleDoubleTapTimeout(seconds: Self.doubleTapWindowSeconds)]

        case (.pressed, .chord):
            phase = .idle
            return [.cancelRecording]

        case (.awaitingSecondTap(let releasedAt), .keyDown):
            guard time - releasedAt <= Self.doubleTapWindowSeconds else {
                // Timer hasn't fired yet but the window has passed: treat as a new press.
                phase = .pressed(since: time)
                return [.cancelRecording, .startRecording]
            }
            phase = .secondTapDown
            return [.enteredHandsFree]

        case (.awaitingSecondTap, .doubleTapTimeout):
            phase = .idle
            return [.cancelRecording]

        case (.secondTapDown, .keyUp):
            phase = .handsFree
            return []

        case (.handsFree, .keyDown):
            phase = .finishingPressDown
            return [.finishRecording]

        case (.finishingPressDown, .keyUp):
            phase = .idle
            return []

        default:
            // Chords in hands-free mode, stray releases, late timeouts: no effect.
            return []
        }
    }
}
