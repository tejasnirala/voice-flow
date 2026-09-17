/// Decisions for inserting a transcript into the focused app. The platform code (pasteboard, events) lives in the
/// app target; the rules live here so they're unit-tested.
public enum InsertionPolicy {
    /// Where the transcript goes when the focused app changed during dictation.
    public enum PasteTarget: String, Codable, Sendable, CaseIterable {
        /// The app (and field) focused when the transcript is ready: dictate, click where the text should go, release.
        /// Default (owner preference, 2026-09-17).
        case currentApp
        /// Only the app focused when the hotkey was pressed; if focus moved, leave the text on the clipboard.
        case dictationApp
    }

    /// Why the transcript was left on the clipboard instead of pasted.
    public enum NotPastedReason: Equatable, Sendable {
        /// VoiceFlow isn't allowed to send ⌘V (System Settings → Privacy & Security → Accessibility).
        case accessibilityNotGranted
        /// A different app is in front than when dictation started; pasting there could put text in the wrong place.
        case focusChanged(from: String, to: String)
        /// No app has focus (e.g. the desktop).
        case noFocusedApp
    }

    public enum Decision: Equatable, Sendable {
        case paste
        case leaveOnClipboard(NotPastedReason)
    }

    /// - Parameters:
    ///   - dictationAppPID / currentAppPID: frontmost app when the hotkey was pressed / now.
    ///   - target: whether a focus change redirects the paste (`.currentApp`) or blocks it (`.dictationApp`).
    public static func decide(accessibilityGranted: Bool,
                              dictationAppPID: Int32?, dictationAppName: String?,
                              currentAppPID: Int32?, currentAppName: String?,
                              target: PasteTarget = .currentApp) -> Decision {
        guard let currentAppPID else { return .leaveOnClipboard(.noFocusedApp) }
        if target == .dictationApp, let dictationAppPID, dictationAppPID != currentAppPID {
            return .leaveOnClipboard(.focusChanged(from: dictationAppName ?? "the previous app",
                                                   to: currentAppName ?? "another app"))
        }
        guard accessibilityGranted else { return .leaveOnClipboard(.accessibilityNotGranted) }
        return .paste
    }

    /// Restore the user's clipboard only if nobody changed it after VoiceFlow wrote the transcript. If the user
    /// copied something meanwhile, their newer content wins.
    public static func shouldRestoreClipboard(changeCountAfterWrite: Int, currentChangeCount: Int) -> Bool {
        changeCountAfterWrite == currentChangeCount
    }

    public static func message(for reason: NotPastedReason) -> String {
        switch reason {
        case .accessibilityNotGranted:
            "Copied to clipboard. Allow VoiceFlow in Accessibility to paste automatically"
        case .focusChanged(let from, let to):
            "Copied to clipboard (not pasted: focus moved from \(from) to \(to))"
        case .noFocusedApp:
            "Copied to clipboard (no app was focused)"
        }
    }
}
