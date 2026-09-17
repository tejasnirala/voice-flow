import AppKit
import AVFoundation

/// Microphone permission. Accessibility (needed to paste) is added in Phase 5.
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

    static func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }
}
