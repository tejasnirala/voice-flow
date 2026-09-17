import AppKit
import VoiceFlowCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?
    private var coordinator: DictationCoordinator?
    private var appState: AppState?
    private var indicator: IndicatorController?
    private var mainWindow: MainWindowController?

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
        let appState = AppState(settings: settings, store: store)
        let indicator = IndicatorController(state: appState)
        let mainWindow = MainWindowController(state: appState)
        coordinator.onStateChange = { [weak menuBar, weak appState, weak indicator, weak coordinator] state in
            menuBar?.update(state: state)
            guard let appState else { return }
            if state != .recording { appState.audioFlowing = false; appState.resetLevels() }
            appState.handsFree = coordinator?.isHandsFree ?? false
            if appState.pipelineState != state {
                appState.pipelineState = state
                indicator?.pipelineChanged(to: state)
            }
        }
        coordinator.onAudioFlowing = { [weak menuBar, weak appState] in
            menuBar?.markAudioFlowing()
            appState?.audioFlowing = true
        }
        // Level metering runs only while the pill is enabled.
        let applyIndicatorSettings = { [weak coordinator, weak appState, weak indicator] (settings: VoiceFlowCore.Settings) in
            coordinator?.onLevel = settings.showIndicator ? { level in appState?.pushLevel(level) } : nil
            indicator?.settingsChanged()
        }
        applyIndicatorSettings(settings)
        appState.onSettingsChanged = { [weak coordinator, weak menuBar] settings in
            coordinator?.updateSettings(settings)
            menuBar?.apply(settings)
            applyIndicatorSettings(settings)
        }
        appState.onCancelDictation = { [weak coordinator] in coordinator?.cancelDictation() }
        appState.onFinishDictation = { [weak coordinator] in coordinator?.finishDictation() }
        appState.onPermissionsMayHaveChanged = { [weak coordinator] in
            guard let coordinator, coordinator.triggerWarning != nil, ModifierKeyMonitor.hasPermission else { return }
            coordinator.activateTrigger()
        }
        menuBar.onOpenWindow = { [weak mainWindow] in mainWindow?.show() }
        menuBar.onDismissError = { [weak coordinator] in coordinator?.dismissError() }
        menuBar.onSettingsChanged = { [weak coordinator, weak appState] settings in
            coordinator?.updateSettings(settings)
            appState?.adopt(settings)
            applyIndicatorSettings(settings)
        }
        menuBar.onRetryTranscription = { [weak coordinator] in coordinator?.retryTranscription() }
        let syncTrigger = { [weak menuBar, weak coordinator] in
            guard let menuBar, let coordinator else { return }
            menuBar.triggerInstructions = coordinator.triggerInstructions
            menuBar.triggerWarning = coordinator.triggerWarning
            menuBar.handsFree = coordinator.isHandsFree
            menuBar.refreshTriggerInfo()
            appState.triggerInstructions = coordinator.triggerInstructions
            appState.triggerWarning = coordinator.triggerWarning
            appState.handsFree = coordinator.isHandsFree
        }
        coordinator.onTriggerInfoChange = syncTrigger
        menuBar.onOpenInputMonitoringSettings = { PermissionManager.openInputMonitoringSettings() }
        // If Input Monitoring was granted since launch, switch to the ⌥ trigger when the menu is next opened.
        menuBar.onMenuWillOpen = { [weak coordinator] in
            guard let coordinator, coordinator.triggerWarning != nil, ModifierKeyMonitor.hasPermission else { return }
            coordinator.activateTrigger()
        }
        coordinator.onSpeechInfoChange = { [weak menuBar, weak appState] status, transcript in
            menuBar?.update(modelStatus: status, lastTranscript: transcript)
            appState?.modelStatus = status
            appState?.lastTranscript = transcript
        }
        coordinator.start()
        self.menuBar = menuBar
        self.coordinator = coordinator
        self.appState = appState
        self.indicator = indicator
        self.mainWindow = mainWindow
        runMeasurementModeIfRequested(coordinator)
        // First launch (no settings yet): show the window with setup. Later launches (e.g. at login) stay in the menu bar.
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "--open-window") {
            // `open VoiceFlow.app --args --open-window modes` (testing, screenshots).
            mainWindow.show(args.indices.contains(index + 1) ? WindowModel.Section(rawValue: args[index + 1]) : nil)
        } else if outcome == .missingUsedDefaults, !args.contains("--measure-recording") {
            mainWindow.show(.home)
        }

        if let start = ProcessInfo.processInfo.kernelStartDate {
            let ms = Date().timeIntervalSince(start) * 1000
            Log.lifecycle.notice("launched in \(ms, format: .fixed(precision: 1), privacy: .public) ms")
        }
    }

    /// Opening VoiceFlow again (Finder, Spotlight, Dock) while it runs shows the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        mainWindow?.show()
        return false
    }

    /// Measurement mode, used by scripts/measure-recording.sh:
    /// `open VoiceFlow.app --args --measure-recording <seconds> [--runs N] [--fresh-engine] [--stay]`
    /// Runs N dictations (each starts 1 s after the previous one completes) without the hotkey, logging recording and
    /// transcription metrics, then quits
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
        coordinator.insertionEnabled = false
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
        coordinator.onDictationComplete = {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { next() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { next() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.shutdown()
        Log.lifecycle.notice("terminating")
    }
}
