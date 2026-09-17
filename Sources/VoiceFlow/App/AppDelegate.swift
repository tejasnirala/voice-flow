import AVFoundation
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
        coordinator.onLanguageResolved = { [weak appState] language in appState?.dictationLanguage = language }
        coordinator.onCycleLanguage = { [weak appState, weak indicator] in
            guard let appState else { return }
            appState.update { $0.language = $0.language.next }
            Log.settings.notice("language switched to \(appState.settings.language.rawValue, privacy: .public)")
            indicator?.showNotice("Language: \(appState.settings.language.displayName)")
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
        coordinator.onSpeechInfoChange = { [weak menuBar, weak appState, weak coordinator] status, transcript in
            menuBar?.modelInstallCommand = coordinator?.modelNeedingInstall?.installCommand
            appState?.modelNeedingInstall = coordinator?.modelNeedingInstall
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
        // `--measure-files a.wav,b.wav [--measure-output out.txt]`: each file is dictated in turn instead of the microphone
        // (tests language routing without speakers); final texts are appended to the output file if given.
        var files: [URL] = []
        if let index = args.firstIndex(of: "--measure-files"), index + 1 < args.count {
            files = args[index + 1].split(separator: ",").map { URL(fileURLWithPath: String($0)) }
            coordinator.injectedAudio = files.compactMap { try? Self.loadMono16k($0) }
            if let outIndex = args.firstIndex(of: "--measure-output"), outIndex + 1 < args.count {
                let out = URL(fileURLWithPath: args[outIndex + 1])
                FileManager.default.createFile(atPath: out.path, contents: nil)
                coordinator.onFinalTextForMeasurement = { text in
                    if let handle = try? FileHandle(forWritingTo: out) {
                        handle.seekToEndOfFile()
                        handle.write(Data((text.replacingOccurrences(of: "\n", with: " ⏎ ") + "\n").utf8))
                        try? handle.close()
                    }
                }
            }
        }
        guard let seconds = files.isEmpty ? value("--measure-recording") : 0.3, seconds > 0 else { return }
        let runs = files.isEmpty ? max(1, Int(value("--runs") ?? 1)) : coordinator.injectedAudio.count
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

    static func loadMono16k(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: file.processingFormat, to: target),
              let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else { return [] }
        try file.read(into: input)
        let capacity = AVAudioFrameCount(Double(input.frameLength) * 16_000 / file.processingFormat.sampleRate) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return [] }
        var supplied = false
        _ = converter.convert(to: output, error: nil) { _, status in
            if supplied { status.pointee = .endOfStream; return nil }
            supplied = true
            status.pointee = .haveData
            return input
        }
        return Array(UnsafeBufferPointer(start: output.floatChannelData![0], count: Int(output.frameLength)))
    }
}
