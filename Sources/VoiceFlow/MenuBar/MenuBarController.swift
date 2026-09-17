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
        case .idle: "Ready — hold \(settings.hotkey.displayName) to dictate"
        case .recording: "🎙 Recording… (Esc to cancel)"
        case .transcribing: "Transcribing…"
        case .processing: "Processing…"
        case .inserting: "Inserting…"
        case .error(let failure): "⚠︎ \(failure.message)"
        }
    }

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
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
        if case .error(let failure) = state {
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

        let modeItem = NSMenuItem(title: "Mode", action: nil, keyEquivalent: "")
        let modes = NSMenu()
        let fast = NSMenuItem(title: "Fast (no LLM)", action: #selector(selectFastMode), keyEquivalent: "")
        fast.target = self
        fast.state = settings.processingMode == .fast ? .on : .off
        modes.addItem(fast)
        let smart = disabled("Smart (local LLM) — not available yet")
        smart.state = settings.processingMode == .smart ? .on : .off
        modes.addItem(smart)
        modes.autoenablesItems = false
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

    @objc private func openMicrophoneSettings() {
        PermissionManager.openMicrophoneSettings()
    }

    @objc private func dismissError() {
        onDismissError?()
    }

    @objc private func selectFastMode() {
        guard settings.processingMode != .fast else { return }
        settings.processingMode = .fast
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
