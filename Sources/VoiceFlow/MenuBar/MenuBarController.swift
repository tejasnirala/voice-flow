import AppKit
import VoiceFlowCore

/// Owns the status item and its menu. The menu is rebuilt only when the user opens it, so an idle app
/// does no UI work.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let settingsStore: SettingsStore
    private var settings: Settings

    init(settingsStore: SettingsStore, settings: Settings) {
        self.settingsStore = settingsStore
        self.settings = settings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        let image = NSImage(systemSymbolName: "mic", accessibilityDescription: BuildInfo.name)
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = BuildInfo.name

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
    }

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        // Pick up edits made in the settings file since the menu was last opened.
        let (loaded, outcome) = settingsStore.load()
        settings = loaded
        if case .invalidUsedDefaults(let path) = outcome {
            Log.settings.error("settings file was invalid; preserved at \(path, privacy: .public), using defaults")
        }
        rebuild(menu)
    }

    private func rebuild(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(disabled("\(BuildInfo.name) \(BuildInfo.version)"))
        menu.addItem(disabled("● Ready"))
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
