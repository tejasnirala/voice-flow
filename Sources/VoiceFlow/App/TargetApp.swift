import AppKit
import ApplicationServices
import VoiceFlowCore

/// The app a dictation goes to, for choosing its text mode (`AppModePolicy`).
/// The focused window's title is read (Accessibility) only for browsers, to recognize AI assistant tabs. It is used for that
/// match and discarded: never stored or logged.
struct TargetApp {
    let bundleID: String?
    let name: String?
    let windowTitle: String?

    @MainActor
    static func detect(_ app: NSRunningApplication?) -> TargetApp {
        guard let app else { return TargetApp(bundleID: nil, name: nil, windowTitle: nil) }
        let bundleID = app.bundleIdentifier
        var title: String?
        if let bundleID, AppModePolicy.browsers.contains(bundleID), AXIsProcessTrusted() {
            let element = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(element, 0.1)   // never stall the pipeline on a busy browser
            var window: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &window) == .success, let window,
               CFGetTypeID(window) == AXUIElementGetTypeID() {
                var value: CFTypeRef?
                if AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &value) == .success {
                    title = value as? String
                }
            }
        }
        return TargetApp(bundleID: bundleID, name: app.localizedName, windowTitle: title)
    }

    func resolve(_ settings: Settings) -> AppModePolicy.Resolution {
        AppModePolicy.resolve(bundleID: bundleID, windowTitle: windowTitle, settings: settings)
    }
}
