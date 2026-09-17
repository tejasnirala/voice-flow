import AppKit
import Darwin
import VoiceFlowCore

// Writes to the speech helper's pipe must fail with an error (not kill the app) if the helper has exited.
signal(SIGPIPE, SIG_IGN)

// `VoiceFlow.app/Contents/MacOS/VoiceFlow --diagnostics`: print the same report as menu → Copy Diagnostics and exit
// (for troubleshooting from Terminal; doesn't start a second menu-bar instance).
if CommandLine.arguments.contains("--diagnostics") {
    let (settings, _) = SettingsStore(directory: SettingsStore.applicationSupportDirectory()).load()
    let status: String = switch STTModelManager.quickStatus(for: settings.sttModel) {
    case .installed: "installed"
    case .missing: "not installed"
    case .corrupted: "damaged"
    case .incompatible: "incompatible"
    }
    Log.lifecycle.notice("diagnostics report requested from the command line")
    print(Diagnostics.report(settings: settings, modelStatus: status, state: "not running (diagnostics)"))
    exit(0)
}

// Menu-bar-only app (LSUIElement): no Dock icon, no main window.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
