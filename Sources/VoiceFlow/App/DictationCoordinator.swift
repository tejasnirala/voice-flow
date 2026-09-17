import Foundation
import VoiceFlowCore

/// Connects hardware/OS events to the `PipelineStateMachine` and performs the side effects of each
/// accepted transition. Phase 2: hotkey only. Audio, STT and insertion are attached in later phases.
@MainActor
final class DictationCoordinator {
    private(set) var machine = PipelineStateMachine()
    private let hotkeys = GlobalHotkeyManager()
    private let settings: Settings
    private var recordingStart: UInt64?

    /// Called after every accepted transition, before its side effects run.
    var onStateChange: ((PipelineState) -> Void)?

    init(settings: Settings) {
        self.settings = settings
    }

    func start() {
        hotkeys.onHotkey = { [weak self] action, phase, latencyMs in
            self?.handleHotkey(action, phase, latencyMs: latencyMs)
        }
        let hotkey = settings.hotkey
        do {
            try hotkeys.register(.dictation, keyCode: hotkey.keyCode, carbonModifiers: hotkey.carbonModifiers)
            Log.hotkey.notice("registered \(hotkey.displayName, privacy: .public)")
        } catch {
            let reason = error.isAlreadyTaken
                ? "\(hotkey.displayName) is already used by another app"
                : "\(hotkey.displayName) couldn't be registered (OSStatus \(error.status))"
            Log.hotkey.error("registration failed: \(reason, privacy: .public)")
            send(.failed(PipelineFailure(stage: .hotkey, message: reason)))
        }
    }

    func dismissError() {
        send(.errorDismissed)
    }

    /// Hotkey events are normally dispatched within ~0.1 ms. While VoiceFlow's own status menu is open, macOS
    /// holds them until the menu closes, then delivers press and release together (observed: 6.4 s late).
    /// Starting a recording from such a stale press would capture nothing useful, so it's ignored.
    static let staleHotkeyThresholdMs = 500.0

    private func handleHotkey(_ action: GlobalHotkeyManager.Action, _ phase: GlobalHotkeyManager.Phase, latencyMs: Double) {
        switch (action, phase) {
        case (.dictation, .pressed) where latencyMs > Self.staleHotkeyThresholdMs:
            Log.hotkey.error("ignored stale press, dispatch latency \(latencyMs, format: .fixed(precision: 0), privacy: .public) ms (menu open?)")
        case (.dictation, .pressed):
            Log.hotkey.notice("pressed, dispatch latency \(latencyMs, format: .fixed(precision: 2), privacy: .public) ms")
            send(.hotkeyPressed)
        case (.dictation, .released):
            Log.hotkey.notice("released, dispatch latency \(latencyMs, format: .fixed(precision: 2), privacy: .public) ms")
            send(.hotkeyReleased)
        case (.cancel, .pressed), (.cancelWithOption, .pressed):
            send(.cancelRequested)
        case (.cancel, .released), (.cancelWithOption, .released):
            break
        }
    }

    private func send(_ event: PipelineEvent) {
        let previous = machine.state
        guard let next = machine.handle(event) else {
            Log.pipeline.info("ignored \(String(describing: event), privacy: .public) in \(String(describing: previous), privacy: .public)")
            return
        }
        Log.pipeline.notice("\(Self.name(previous), privacy: .public) → \(Self.name(next), privacy: .public)")
        onStateChange?(next)
        runEffects(from: previous, to: next)
    }

    private func runEffects(from previous: PipelineState, to next: PipelineState) {
        if next == .recording, previous != .recording {
            recordingStart = DispatchTime.now().uptimeNanoseconds
            registerCancelKeys()
        }
        if previous == .recording, next != .recording {
            hotkeys.unregister(.cancel)
            hotkeys.unregister(.cancelWithOption)
        }

        switch next {
        case .idle where previous == .recording:
            Log.pipeline.notice("recording cancelled")
        case .transcribing:
            let heldMs = recordingStart.map { Double(DispatchTime.now().uptimeNanoseconds - $0) / 1_000_000 } ?? 0
            Log.pipeline.notice("hotkey held \(heldMs, format: .fixed(precision: 0), privacy: .public) ms")
            // Phase 2 stub: no audio or STT yet, so the dictation ends with nothing to insert.
            send(.transcriptionEmpty)
        default:
            break
        }
    }

    private func registerCancelKeys() {
        let esc = UInt32(53), option = UInt32(0x0800)
        do {
            try hotkeys.register(.cancel, keyCode: esc, carbonModifiers: 0)
            try hotkeys.register(.cancelWithOption, keyCode: esc, carbonModifiers: option)
        } catch {
            // Not fatal: dictation still works; only Esc-to-cancel is unavailable.
            Log.hotkey.error("Esc cancel registration failed (OSStatus \(error.status))")
        }
    }

    private static func name(_ state: PipelineState) -> String {
        switch state {
        case .error: "error"
        default: String(describing: state)
        }
    }
}
