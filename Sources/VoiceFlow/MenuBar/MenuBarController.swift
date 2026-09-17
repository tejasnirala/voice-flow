import AppKit
import VoiceFlowCore

/// Owns the status item and its menu. The menu is rebuilt only when the user opens it, so an idle app
/// does no UI work.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let settingsStore: SettingsStore
    private var settings: Settings
    private var state: PipelineState = .idle
    /// Called when the user dismisses an error from the menu.
    var onDismissError: (() -> Void)?
    /// Called when settings are reloaded or changed from the menu.
    var onSettingsChanged: ((Settings) -> Void)?
    var onRetryTranscription: (() -> Void)?
    var onOpenInputMonitoringSettings: (() -> Void)?
    /// Supplied by the coordinator: instructions for the active trigger, a fallback warning, hands-free state.
    var triggerInstructions = "hold ⌥ to dictate"
    var triggerWarning: String?
    var handsFree = false
    private var modelStatus: STTModelStatus = .installed
    /// Held only in memory for display and copying.
    private var lastTranscript: String?

    func update(modelStatus: STTModelStatus, lastTranscript: String?) {
        self.modelStatus = modelStatus
        self.lastTranscript = lastTranscript
        if let menu = statusItem.menu, menu.numberOfItems > 0 { rebuild(menu) }
    }

    init(settingsStore: SettingsStore, settings: Settings) {
        self.settingsStore = settingsStore
        self.settings = settings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        update(state: .idle)

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
    }

    /// Reflects the pipeline state in the icon immediately; the menu text is refreshed when opened.
    func update(state: PipelineState) {
        self.state = state
        guard let button = statusItem.button else { return }
        let symbol: String
        switch state {
        case .idle: symbol = "mic"
        case .recording: symbol = "mic.fill"
        case .transcribing, .processing: symbol = "waveform"
        case .inserting: symbol = "text.cursor"
        case .error: symbol = "exclamationmark.triangle"
        }
        var image = NSImage(systemSymbolName: symbol, accessibilityDescription: "\(BuildInfo.name): \(statusText)")
        if state == .recording {
            // Red while recording so it's obvious the microphone is live. The menu bar ignores
            // `contentTintColor` for status items here, so bake the color into a non-template symbol.
            image = image?.withSymbolConfiguration(.init(paletteColors: [.systemRed]))
            image?.isTemplate = false
        } else {
            image?.isTemplate = true
        }
        button.image = image
        button.toolTip = "\(BuildInfo.name) — \(statusText)"
        if let menu = statusItem.menu, menu.numberOfItems > 0 { rebuild(menu) }
    }

    private var statusText: String {
        switch state {
        case .idle: "Ready — \(triggerInstructions)"
        case .recording: handsFree ? "🎙 Hands-free — press ⌥ to finish, Esc to cancel" : "🎙 Recording… (Esc to cancel)"
        case .transcribing: "Transcribing on this Mac…"
        case .processing: "Smart rewrite on this Mac…"
        case .inserting: "Pasting…"
        case .error(let failure): "⚠︎ \(failure.message)"
        }
    }

    // MARK: NSMenuDelegate

    /// Refreshes trigger text without reloading settings (e.g. hands-free toggled).
    func refreshTriggerInfo() {
        if let menu = statusItem.menu, menu.numberOfItems > 0 { rebuild(menu) }
        update(state: state)
    }

    /// Called just before the menu opens.
    var onMenuWillOpen: (() -> Void)?

    func menuNeedsUpdate(_ menu: NSMenu) {
        onMenuWillOpen?()
        // Pick up edits made in the settings file since the menu was last opened.
        let (loaded, outcome) = settingsStore.load()
        if loaded != settings { onSettingsChanged?(loaded) }
        settings = loaded
        if case .invalidUsedDefaults(let path) = outcome {
            Log.settings.error("settings file was invalid; preserved at \(path, privacy: .public), using defaults")
        }
        rebuild(menu)
    }

    private func rebuild(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(disabled("\(BuildInfo.name) \(BuildInfo.version)"))
        menu.addItem(disabled(statusText))
        if let triggerWarning {
            menu.addItem(disabled("⚠︎ \(triggerWarning)"))
            let open = NSMenuItem(title: "Open Input Monitoring Settings…", action: #selector(openInputMonitoringSettings), keyEquivalent: "")
            open.target = self
            menu.addItem(open)
        }
        if state == .idle, modelStatus != .installed {
            menu.addItem(disabled("⚠︎ Speech model \(modelStatusText) — run \(settings.sttModel.installCommand)"))
        }
        if !PermissionManager.isAccessibilityTrusted, !(state.isErrorWithRecovery(.openAccessibilitySettings)) {
            menu.addItem(disabled("⚠︎ Accessibility not allowed — text is copied, not pasted"))
            let open = NSMenuItem(title: "Open Accessibility Settings…", action: #selector(openAccessibilitySettings), keyEquivalent: "")
            open.target = self
            menu.addItem(open)
        }
        if case .error(let failure) = state {
            if failure.recovery == .retryTranscription {
                let retry = NSMenuItem(title: "Retry Transcription", action: #selector(retryTranscription), keyEquivalent: "")
                retry.target = self
                menu.addItem(retry)
            }
            if failure.recovery == .openAccessibilitySettings {
                let open = NSMenuItem(title: "Open Accessibility Settings…", action: #selector(openAccessibilitySettings), keyEquivalent: "")
                open.target = self
                menu.addItem(open)
            }
            if failure.recovery == .openMicrophoneSettings {
                let open = NSMenuItem(title: "Open Microphone Settings…", action: #selector(openMicrophoneSettings), keyEquivalent: "")
                open.target = self
                menu.addItem(open)
            }
            let dismiss = NSMenuItem(title: "Dismiss", action: #selector(dismissError), keyEquivalent: "")
            dismiss.target = self
            menu.addItem(dismiss)
        }
        menu.addItem(.separator())

        if let transcript = lastTranscript {
            let preview = transcript.count > 60 ? transcript.prefix(60) + "…" : Substring(transcript)
            menu.addItem(disabled("Last: \(preview)"))
            let copy = NSMenuItem(title: "Copy Last Transcript", action: #selector(copyLastTranscript), keyEquivalent: "c")
            copy.target = self
            menu.addItem(copy)
            menu.addItem(.separator())
        }

        let modelReason = OnDeviceRewriter.unavailableReason
        let modeItem = NSMenuItem(title: "Mode: \(settings.textMode.displayName)", action: nil, keyEquivalent: "")
        let modes = NSMenu()
        modes.autoenablesItems = false
        let descriptions: [TextMode: String] = [
            .raw: "Raw — exactly as recognized",
            .clean: "Clean — punctuation, no fillers or stutters",
            .developer: "Developer — Clean + package.json, --flags, user_id",
            .prompt: "Prompt — clear prompt for an AI (on-device model)",
            .writing: "Writing — polished prose (on-device model)",
        ]
        for mode in TextMode.allCases {
            let item = NSMenuItem(title: descriptions[mode] ?? mode.displayName, action: #selector(selectTextMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = settings.textMode == mode ? .on : .off
            if mode.requiresModel, let modelReason {
                item.title += " — \(modelReason)"
                item.isEnabled = false
            }
            modes.addItem(item)
        }
        modes.addItem(.separator())
        let smart = NSMenuItem(title: modelReason == nil ? "Smart Rewrite for Clean & Developer (on-device model, +~0.8 s)"
                                                         : "Smart Rewrite — \(modelReason!)",
                               action: #selector(toggleSmartRewrite), keyEquivalent: "")
        smart.target = self
        smart.isEnabled = modelReason == nil
        smart.state = settings.processingMode == .smart ? .on : .off
        modes.addItem(smart)
        modeItem.submenu = modes
        menu.addItem(modeItem)

        menu.addItem(.separator())
        let open = NSMenuItem(title: "Open Settings File…", action: #selector(openSettingsFile), keyEquivalent: ",")
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit \(BuildInfo.name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    // MARK: Actions

    private var modelStatusText: String {
        switch modelStatus {
        case .installed: "installed"
        case .missing: "not installed"
        case .corrupted: "damaged"
        case .incompatible: "incompatible"
        }
    }

    @objc private func retryTranscription() {
        onRetryTranscription?()
    }

    @objc private func copyLastTranscript() {
        guard let lastTranscript else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastTranscript, forType: .string)
    }

    @objc private func openInputMonitoringSettings() {
        onOpenInputMonitoringSettings?()
    }

    @objc private func openAccessibilitySettings() {
        PermissionManager.openAccessibilitySettings()
    }

    @objc private func openMicrophoneSettings() {
        PermissionManager.openMicrophoneSettings()
    }

    @objc private func dismissError() {
        onDismissError?()
    }

    @objc private func selectTextMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = TextMode(rawValue: raw), settings.textMode != mode else { return }
        settings.textMode = mode
        persist()
    }

    @objc private func toggleSmartRewrite() {
        settings.processingMode = settings.processingMode == .smart ? .fast : .smart
        persist()
    }

    @objc private func openSettingsFile() {
        // Create the file on first use only; the app doesn't write anything just by running.
        if !FileManager.default.fileExists(atPath: settingsStore.fileURL.path) { persist() }
        NSWorkspace.shared.open(settingsStore.fileURL)
    }

    private func persist() {
        do {
            try settingsStore.save(settings)
            onSettingsChanged?(settings)
            Log.settings.notice("settings saved")
        } catch {
            Log.settings.error("failed to save settings: \(error.localizedDescription, privacy: .public)")
            let alert = NSAlert()
            alert.messageText = "VoiceFlow couldn't save its settings"
            alert.informativeText = "\(settingsStore.fileURL.path)\n\n\(error.localizedDescription)"
            alert.runModal()
        }
    }
}

private extension PipelineState {
    func isErrorWithRecovery(_ recovery: PipelineFailure.Recovery) -> Bool {
        if case .error(let failure) = self { return failure.recovery == recovery }
        return false
    }
}
