import AppKit
import AVFoundation

/// Microphone (recording) and Accessibility (posting ⌘V to paste) permissions.
@MainActor
enum PermissionManager {
    enum Microphone { case authorized, notDetermined, denied }

    static var microphone: Microphone {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: .authorized
        case .notDetermined: .notDetermined
        default: .denied // .denied or .restricted
        }
    }

    /// Shows the system prompt (first use only).
    static func requestMicrophone(completion: @escaping @MainActor (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    /// Whether VoiceFlow may post keyboard events (required to paste).
    static var isAccessibilityTrusted: Bool { AXIsProcessTrusted() }

    private static var accessibilityPromptShown = false

    /// Shows the system's "allow in Accessibility" prompt, at most once per launch.
    static func requestAccessibility() {
        guard !accessibilityPromptShown else { return }
        accessibilityPromptShown = true
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    static func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    static func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }
}
