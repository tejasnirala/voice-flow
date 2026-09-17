import AppKit
import Carbon.HIToolbox
import VoiceFlowCore

/// Inserts a transcript into the focused app: snapshot clipboard → write transcript → ⌘V → restore clipboard.
/// If pasting isn't allowed or safe (see `InsertionPolicy`), the transcript is left on the clipboard so it's never lost.
@MainActor
final class TextInserter {
    enum Outcome: Equatable {
        /// ⌘V was posted; the clipboard restore is scheduled.
        case pasted
        case leftOnClipboard(InsertionPolicy.NotPastedReason)
    }

    struct Metrics {
        var snapshotMs: Double
        var snapshotItems: Int
        var snapshotBytes: Int
        var writeMs: Double
        var pasteEventMs: Double
    }

    /// How long to wait after ⌘V before restoring the clipboard. The target app reads the pasteboard while handling
    /// the key event, asynchronously; too short a delay would paste the restored (old) content instead.
    var restoreDelaySeconds = 0.25

    private let clipboard: ClipboardManager

    init(clipboard: ClipboardManager = ClipboardManager()) {
        self.clipboard = clipboard
    }

    func insert(_ text: String, dictationApp: NSRunningApplication?,
                completion: @escaping (_ outcome: Outcome, _ metrics: Metrics, _ restored: Bool?) -> Void) {
        let current = NSWorkspace.shared.frontmostApplication
        let decision = InsertionPolicy.decide(
            accessibilityGranted: PermissionManager.isAccessibilityTrusted,
            dictationAppPID: dictationApp?.processIdentifier, dictationAppName: dictationApp?.localizedName,
            currentAppPID: current?.processIdentifier, currentAppName: current?.localizedName)

        var metrics = Metrics(snapshotMs: 0, snapshotItems: 0, snapshotBytes: 0, writeMs: 0, pasteEventMs: 0)

        guard decision == .paste else {
            // Never lose speech: leave the transcript on the clipboard (no restore) and report why.
            let t = DispatchTime.now().uptimeNanoseconds
            clipboard.write(transcript: text)
            metrics.writeMs = Self.ms(since: t)
            if case .leaveOnClipboard(let reason) = decision {
                if reason == .accessibilityNotGranted { PermissionManager.requestAccessibility() }
                completion(.leftOnClipboard(reason), metrics, nil)
            }
            return
        }

        var t = DispatchTime.now().uptimeNanoseconds
        let saved = clipboard.snapshot()
        metrics.snapshotMs = Self.ms(since: t)
        metrics.snapshotItems = saved.items.count
        metrics.snapshotBytes = saved.items.flatMap { $0 }.reduce(0) { $0 + $1.data.count }

        t = DispatchTime.now().uptimeNanoseconds
        let changeCountAfterWrite = clipboard.write(transcript: text)
        metrics.writeMs = Self.ms(since: t)

        t = DispatchTime.now().uptimeNanoseconds
        Self.postCommandV()
        metrics.pasteEventMs = Self.ms(since: t)
        completion(.pasted, metrics, nil)

        let clipboard = self.clipboard
        DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelaySeconds) {
            let restore = InsertionPolicy.shouldRestoreClipboard(changeCountAfterWrite: changeCountAfterWrite,
                                                                 currentChangeCount: clipboard.changeCount)
            if restore { clipboard.restore(saved) }
            completion(.pasted, metrics, restore)
        }
    }

    /// Posts ⌘V. The event carries only the Command flag, so a still-held ⌥ (from the hotkey) doesn't turn it into ⌥⌘V.
    private static func postCommandV() {
        let source = CGEventSource(stateID: .privateState)
        let v = CGKeyCode(kVK_ANSI_V)
        let down = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private static func ms(since start: UInt64) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }
}
