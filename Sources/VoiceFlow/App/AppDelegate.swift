import AppKit
import VoiceFlowCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = SettingsStore(directory: SettingsStore.applicationSupportDirectory())
        let (settings, outcome) = store.load()
        switch outcome {
        case .loaded: Log.settings.info("settings loaded")
        case .missingUsedDefaults: Log.settings.info("no settings file; using defaults")
        case .invalidUsedDefaults(let path):
            Log.settings.error("settings file was invalid; preserved at \(path, privacy: .public), using defaults")
        }

        menuBar = MenuBarController(settingsStore: store, settings: settings)

        if let start = ProcessInfo.processInfo.kernelStartDate {
            let ms = Date().timeIntervalSince(start) * 1000
            Log.lifecycle.notice("launched in \(ms, format: .fixed(precision: 1), privacy: .public) ms")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Log.lifecycle.notice("terminating")
    }
}
