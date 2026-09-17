import AppKit
import VoiceFlowCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?
    private var coordinator: DictationCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = SettingsStore(directory: SettingsStore.applicationSupportDirectory())
        let (settings, outcome) = store.load()
        switch outcome {
        case .loaded: Log.settings.info("settings loaded")
        case .missingUsedDefaults: Log.settings.info("no settings file; using defaults")
        case .invalidUsedDefaults(let path):
            Log.settings.error("settings file was invalid; preserved at \(path, privacy: .public), using defaults")
        }

        let menuBar = MenuBarController(settingsStore: store, settings: settings)
        let coordinator = DictationCoordinator(settings: settings)
        coordinator.onStateChange = { [weak menuBar] state in menuBar?.update(state: state) }
        menuBar.onDismissError = { [weak coordinator] in coordinator?.dismissError() }
        menuBar.onSettingsChanged = { [weak coordinator] settings in coordinator?.updateSettings(settings) }
        coordinator.start()
        self.menuBar = menuBar
        self.coordinator = coordinator
        runMeasurementModeIfRequested(coordinator)

        if let start = ProcessInfo.processInfo.kernelStartDate {
            let ms = Date().timeIntervalSince(start) * 1000
            Log.lifecycle.notice("launched in \(ms, format: .fixed(precision: 1), privacy: .public) ms")
        }
    }

    /// Measurement mode, used by scripts/measure-recording.sh:
    /// `open VoiceFlow.app --args --measure-recording <seconds> [--runs N] [--fresh-engine] [--stay]`
    /// Records N times (1 s apart) without the hotkey, logging each recording's metrics, then quits
    /// (or stays running with `--stay` so idle cost after recording can be sampled).
    private func runMeasurementModeIfRequested(_ coordinator: DictationCoordinator) {
        let args = ProcessInfo.processInfo.arguments
        func value(_ flag: String) -> Double? {
            args.firstIndex(of: flag).flatMap { $0 + 1 < args.count ? Double(args[$0 + 1]) : nil }
        }
        guard let seconds = value("--measure-recording"), seconds > 0 else { return }
        let runs = max(1, Int(value("--runs") ?? 1))
        let stay = args.contains("--stay")
        coordinator.reuseAudioEngine = !args.contains("--fresh-engine")
        Log.lifecycle.notice("measurement mode: \(runs, privacy: .public) × \(seconds, format: .fixed(precision: 1), privacy: .public) s, reuse engine \(coordinator.reuseAudioEngine, privacy: .public)")

        var remaining = runs
        func next() {
            guard remaining > 0 else {
                if !stay { NSApp.terminate(nil) }
                return
            }
            remaining -= 1
            guard coordinator.startRecordingProgrammatically() else {
                Log.lifecycle.error("measurement mode: recording did not start")
                NSApp.terminate(nil)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { coordinator.stopRecordingProgrammatically() }
        }
        coordinator.onRecordingFinished = {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { next() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { next() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Log.lifecycle.notice("terminating")
    }
}
