import AppKit
import SwiftUI
import VoiceFlowCore

/// The VoiceFlow window (Home, Modes, Apps, Dictionary, Settings, About). Created when opened and released when
/// closed, so it costs nothing while you just dictate. While it's open VoiceFlow shows in the Dock and app switcher.
@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    private let state: AppState
    private var window: NSWindow?
    private var model: WindowModel?

    init(state: AppState) {
        self.state = state
    }

    func show(_ section: WindowModel.Section? = nil) {
        if window == nil {
            let model = WindowModel()
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.title = BuildInfo.name
            window.titlebarAppearsTransparent = true
            window.minSize = NSSize(width: 700, height: 460)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentView = NSHostingView(rootView: MainView(state: state, model: model))
            window.center()
            window.setFrameAutosaveName("VoiceFlowMainWindow")
            self.window = window
            self.model = model
        }
        if let section { model?.section = section }
        MainMenu.install()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window?.contentView = nil
        window = nil
        model = nil
        // Back to a menu-bar-only app.
        NSApp.setActivationPolicy(.accessory)
    }
}

/// App menu bar while the window is open (Quit, Close, and Edit so ⌘C/⌘V work in text fields).
@MainActor
enum MainMenu {
    static func install() {
        guard NSApp.mainMenu == nil || NSApp.mainMenu?.items.isEmpty == true else { return }
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Hide \(BuildInfo.name)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit \(BuildInfo.name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.mainMenu = main
        NSApp.windowsMenu = windowMenu
    }
}

/// View-local state for the window (SwiftUI's `@State` macro plugin ships only with Xcode).
@MainActor
@Observable
final class WindowModel {
    enum Section: String, CaseIterable, Identifiable {
        case home, modes, apps, dictionary, settings, about
        var id: String { rawValue }
        var title: String {
            switch self {
            case .home: "Home"
            case .modes: "Modes"
            case .apps: "Apps"
            case .dictionary: "Dictionary"
            case .settings: "Settings"
            case .about: "About"
            }
        }
        var symbol: String {
            switch self {
            case .home: "house"
            case .modes: "text.badge.checkmark"
            case .apps: "square.grid.2x2"
            case .dictionary: "character.book.closed"
            case .settings: "gearshape"
            case .about: "info.circle"
            }
        }
    }

    var section: Section? = .home
    // Home
    var microphone = "unknown"
    var accessibility = false
    var inputMonitoring = false
    var encoderInstalled = false
    var rewriteUnavailable: String?
    var openAtLogin = false
    // Dictionary drafts
    var dictionary = UserDictionary.empty
    var newTerm = ""
    var newSpoken = ""
    var newWritten = ""
    var copiedNotice: String?
}

struct MainView: View {
    let state: AppState
    @Bindable var model: WindowModel

    var body: some View {
        NavigationSplitView {
            List(selection: $model.section) {
                ForEach(WindowModel.Section.allCases) { section in
                    Label(section.title, systemImage: section.symbol).tag(section)
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch model.section ?? .home {
                    case .home: HomeView(state: state, model: model)
                    case .modes: ModesView(state: state, model: model)
                    case .apps: AppsView(state: state)
                    case .dictionary: DictionaryView(state: state, model: model)
                    case .settings: SettingsView(state: state, model: model)
                    case .about: AboutView(state: state, model: model)
                    }
                }
                .padding(28)
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Shared pieces

struct SectionHeader: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.largeTitle.weight(.semibold))
            Text(subtitle).foregroundStyle(.secondary)
        }
    }
}

struct Card<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.08)))
    }
}

struct StatusRow: View {
    let ok: Bool
    let title: String
    let detail: String
    var action: (String, () -> Void)?
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(ok ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(detail).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Spacer()
            if let action, !ok { Button(action.0, action: action.1) }
        }
    }
}

func modeDescription(_ mode: TextMode) -> String {
    switch mode {
    case .raw: "Exactly as recognized."
    case .clean: "Removes um/uh and stutters, fixes capitals and punctuation."
    case .developer: "Clean + package.json, --flags, user_id, kubectl, useEffect."
    case .prompt: "Turns spoken thoughts into a clear prompt for an AI assistant (on-device model)."
    case .writing: "Polished sentences for messages and notes (on-device model)."
    case .code: "For terminals and editors: symbols, no capitals or final period."
    }
}

func copyToClipboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}

// MARK: - Home

struct HomeView: View {
    let state: AppState
    @Bindable var model: WindowModel

    var body: some View {
        SectionHeader(title: "Home", subtitle: "Dictation that runs entirely on this Mac.")
        Card {
            HStack(spacing: 14) {
                Image(systemName: state.pipelineState == .recording ? "mic.fill" : "mic")
                    .font(.system(size: 28))
                    .foregroundStyle(state.pipelineState == .recording ? .red : .accentColor)
                    .frame(width: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(statusTitle).font(.title3.weight(.semibold))
                    Text(state.triggerWarning ?? "\(state.triggerInstructions.prefix(1).uppercased() + state.triggerInstructions.dropFirst()). Esc cancels.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        if let transcript = state.lastTranscript {
            Card {
                HStack {
                    Text("Last dictation").font(.headline)
                    Spacer()
                    Button("Copy") { copyToClipboard(transcript) }
                }
                Text(transcript).textSelection(.enabled).foregroundStyle(.secondary)
                Text("Kept in memory only, never saved.").font(.caption).foregroundStyle(.tertiary)
            }
        }
        Text("Setup").font(.title2.weight(.semibold)).padding(.top, 4)
        Card {
            StatusRow(ok: model.microphone == "authorized", title: "Microphone",
                      detail: model.microphone == "authorized" ? "Allowed" : "Needed to hear you. Only used while you dictate.",
                      action: ("Allow…", {
                          if model.microphone == "notDetermined" {
                              PermissionManager.requestMicrophone { _ in refresh() }
                          } else {
                              PermissionManager.openMicrophoneSettings()
                          }
                      }))
            Divider()
            StatusRow(ok: model.inputMonitoring, title: "Input Monitoring",
                      detail: model.inputMonitoring ? "Allowed: the ⌥ key works on its own" : "Needed for the ⌥ trigger (otherwise ⌥Space).",
                      action: ("Allow…", {
                          ModifierKeyMonitor.requestPermission()
                          PermissionManager.openInputMonitoringSettings()
                      }))
            Divider()
            StatusRow(ok: model.accessibility, title: "Accessibility",
                      detail: model.accessibility ? "Allowed: text is pasted where you're typing" : "Needed to paste. Without it, text is copied to the clipboard.",
                      action: ("Allow…", { PermissionManager.requestAccessibility(); PermissionManager.openAccessibilitySettings() }))
            Divider()
            let missing = state.modelNeedingInstall
            StatusRow(ok: missing == nil, title: missing.map { "Speech model (\($0.id))" } ?? "Speech models",
                      detail: missing.map { "Run in Terminal: \($0.installCommand)" } ?? "Installed for your language setting",
                      action: ("Copy Command", { copyToClipboard(missing?.installCommand ?? "") }))
            if let command = state.settings.sttModel.coreMLEncoderInstallCommand {
                Divider()
                StatusRow(ok: model.encoderInstalled, title: "Neural Engine encoder",
                          detail: model.encoderInstalled ? "Installed: ~25% faster transcription" : "Optional, ~25% faster. Run: \(command)",
                          action: ("Copy Command", { copyToClipboard(command) }))
            }
            Divider()
            StatusRow(ok: model.rewriteUnavailable == nil, title: "Apple on-device model",
                      detail: model.rewriteUnavailable.map { "Prompt, Writing and Smart Rewrite need it: \($0)" } ?? "Available for Prompt, Writing and Smart Rewrite")
        }
        .task {
            // Permissions change in System Settings; refresh while this page is visible.
            while !Task.isCancelled {
                refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private var statusTitle: String {
        switch state.pipelineState {
        case .idle: "Ready"
        case .recording: state.handsFree ? "Listening (hands-free)" : "Listening"
        case .transcribing: "Transcribing…"
        case .processing: "Rewriting…"
        case .inserting: "Pasting…"
        case .error(let failure): failure.message
        }
    }

    private func refresh() {
        let mic = "\(PermissionManager.microphone)"
        let ax = PermissionManager.isAccessibilityTrusted
        let im = ModifierKeyMonitor.hasPermission
        let changed = mic != model.microphone || ax != model.accessibility || im != model.inputMonitoring
        // Assign only on change: every assignment to an @Observable property redraws the page.
        if model.microphone != mic { model.microphone = mic }
        if model.accessibility != ax { model.accessibility = ax }
        if model.inputMonitoring != im { model.inputMonitoring = im }
        let encoder = STTModelManager.hasCoreMLEncoder(for: state.settings.sttModel)
        if model.encoderInstalled != encoder { model.encoderInstalled = encoder }
        let rewrite = OnDeviceRewriter.unavailableReason
        if model.rewriteUnavailable != rewrite { model.rewriteUnavailable = rewrite }
        if changed { state.onPermissionsMayHaveChanged?() }
    }
}

// MARK: - Modes

struct ModesView: View {
    let state: AppState
    @Bindable var model: WindowModel

    var body: some View {
        SectionHeader(title: "Modes", subtitle: "How your words are turned into text. Nothing is added that you didn't say.")
        Card {
            Text("Default mode").font(.headline)
            Text(state.settings.modeByApp ? "Used in apps without their own mode (see Apps)." : "Used everywhere.")
                .font(.callout).foregroundStyle(.secondary)
            ForEach(TextMode.allCases, id: \.self) { mode in
                let unavailable = mode.requiresModel ? OnDeviceRewriter.unavailableReason : nil
                Button {
                    state.update { $0.textMode = mode }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: state.settings.textMode == mode ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(state.settings.textMode == mode ? Color.accentColor : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mode.displayName).font(.body.weight(.medium))
                            Text(unavailable ?? modeDescription(mode)).font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(unavailable != nil)
            }
        }
        Card {
            Toggle(isOn: Binding(get: { state.settings.processingMode == .smart },
                                 set: { on in state.update { $0.processingMode = on ? .smart : .fast } })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Smart Rewrite for Clean & Developer").font(.body.weight(.medium))
                    Text("Apple's on-device model fixes grammar and makes lists; a safety check rejects any change to your words. Adds ~1 s; skipped for dictations of 10 words or fewer.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            .disabled(OnDeviceRewriter.unavailableReason != nil)
            Divider()
            Toggle(isOn: Binding(get: { state.settings.modeByApp }, set: { on in state.update { $0.modeByApp = on } })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Choose mode by app").font(.body.weight(.medium))
                    Text("VS Code → Developer, Slack → Clean, ChatGPT → Prompt, Notes → Writing. Customize under Apps.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Apps

struct AppsView: View {
    let state: AppState

    var body: some View {
        SectionHeader(title: "Apps", subtitle: "The mode used in each app. Your choices override the built-in defaults.")
        if !state.settings.modeByApp {
            Card {
                Label("Choose mode by app is off, so the default mode is used everywhere.", systemImage: "info.circle")
                Button("Turn On") { state.update { $0.modeByApp = true } }
            }
        }
        Card {
            HStack {
                Text("Your choices").font(.headline)
                Spacer()
                Button("Add App…", action: addApp)
            }
            Text("Mode and language per app. \"Automatic\" uses the built-in default mode; \"Same as everywhere\" uses your language setting (\(state.settings.language.displayName)).")
                .font(.callout).foregroundStyle(.secondary)
            if ownerApps.isEmpty {
                Text("None yet. Add an app to pick its mode or language (e.g. WhatsApp → Hinglish).").foregroundStyle(.secondary)
            }
            ForEach(ownerApps, id: \.self) { bundleID in
                HStack(spacing: 10) {
                    AppIconName(bundleID: bundleID)
                    Spacer()
                    Picker("", selection: Binding<TextMode?>(get: { state.settings.appModes[bundleID] },
                                                           set: { mode in state.update { $0.appModes[bundleID] = mode } })) {
                        Text("Automatic").tag(TextMode?.none)
                        ForEach(TextMode.allCases, id: \.self) { Text($0.displayName).tag(TextMode?.some($0)) }
                    }
                    .labelsHidden()
                    .frame(width: 120)
                    Picker("", selection: Binding<DictationLanguage?>(get: { state.settings.appLanguages[bundleID] },
                                                                    set: { value in state.update { $0.appLanguages[bundleID] = value } })) {
                        Text("Same as everywhere").tag(DictationLanguage?.none)
                        ForEach(DictationLanguage.allCases.filter { $0 != .auto }, id: \.self) { Text($0.displayName).tag(DictationLanguage?.some($0)) }
                    }
                    .labelsHidden()
                    .frame(width: 170)
                    Button {
                        state.update { $0.appModes[bundleID] = nil; $0.appLanguages[bundleID] = nil }
                    } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                        .help("Remove this app's choices")
                }
            }
        }
        Card {
            Text("Built-in defaults (installed apps)").font(.headline)
            Text("Browser tabs titled ChatGPT, Claude, Gemini or Perplexity use Prompt.").font(.callout).foregroundStyle(.secondary)
            ForEach(builtInInstalled, id: \.0) { bundleID, mode in
                HStack {
                    AppIconName(bundleID: bundleID)
                    Spacer()
                    Text(mode.displayName).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Apps with an owner mode or language (kept in the list while either is set).
    private var ownerApps: [String] {
        Array(Set(state.settings.appModes.keys).union(state.settings.appLanguages.keys))
            .sorted { AppIconName.name(for: $0) < AppIconName.name(for: $1) }
    }

    private var builtInInstalled: [(String, TextMode)] {
        AppModePolicy.builtIn
            .filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.key) != nil && !ownerApps.contains($0.key) }
            .sorted { AppIconName.name(for: $0.key) < AppIconName.name(for: $1.key) }
            .map { ($0.key, $0.value) }
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Add"
        guard panel.runModal() == .OK, let url = panel.url, let bundleID = Bundle(url: url)?.bundleIdentifier else { return }
        // Added apps start on automatic mode and the global language; pick either in the row.
        state.update { if $0.appModes[bundleID] == nil && $0.appLanguages[bundleID] == nil { $0.appModes[bundleID] = AppModePolicy.builtInMode(for: bundleID) ?? $0.textMode } }
    }
}

struct AppIconName: View {
    let bundleID: String

    static func name(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    var body: some View {
        HStack(spacing: 8) {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 20, height: 20)
            } else {
                Image(systemName: "app.dashed").frame(width: 20, height: 20)
            }
            Text(Self.name(for: bundleID))
        }
    }
}

// MARK: - Dictionary

struct DictionaryView: View {
    let state: AppState
    @Bindable var model: WindowModel

    var body: some View {
        SectionHeader(title: "Dictionary", subtitle: "Your own words and spellings. Used in every mode except Raw.")
        Card {
            Text("Terms").font(.headline)
            Text("Spelled exactly like this and recognized more reliably (e.g. Supabase, tRPC). Up to 40 help recognition.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                TextField("Add a term", text: $model.newTerm).onSubmit(addTerm)
                Button("Add", action: addTerm).disabled(model.newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            ForEach(Array(model.dictionary.terms.enumerated()), id: \.offset) { index, term in
                HStack {
                    Text(term)
                    Spacer()
                    Button { model.dictionary.terms.remove(at: index); save() } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                }
            }
        }
        Card {
            Text("Replacements").font(.headline)
            Text("When you say the first, write the second (e.g. \"voice flow\" → VoiceFlow).").font(.callout).foregroundStyle(.secondary)
            HStack {
                TextField("Spoken", text: $model.newSpoken)
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                TextField("Written", text: $model.newWritten).onSubmit(addReplacement)
                Button("Add", action: addReplacement)
                    .disabled(model.newSpoken.trimmingCharacters(in: .whitespaces).isEmpty || model.newWritten.isEmpty)
            }
            ForEach(Array(model.dictionary.replacements.enumerated()), id: \.offset) { index, pair in
                HStack {
                    Text(pair.spoken)
                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                    Text(pair.written).font(.body.weight(.medium))
                    Spacer()
                    Button { model.dictionary.replacements.remove(at: index); save() } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                }
            }
        }
        Button("Open dictionary.json") {
            if !FileManager.default.fileExists(atPath: state.dictionaryURL.path) { save() }
            NSWorkspace.shared.open(state.dictionaryURL)
        }
        .buttonStyle(.link)
        .onAppear { model.dictionary = state.loadDictionary() }
    }

    private func addTerm() {
        let term = model.newTerm.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty, !model.dictionary.terms.contains(term) else { return }
        model.dictionary.terms.append(term)
        model.newTerm = ""
        save()
    }

    private func addReplacement() {
        let spoken = model.newSpoken.trimmingCharacters(in: .whitespaces)
        let written = model.newWritten.trimmingCharacters(in: .whitespaces)
        guard !spoken.isEmpty, !written.isEmpty else { return }
        model.dictionary.replacements.append(.init(spoken: spoken, written: written))
        model.newSpoken = ""
        model.newWritten = ""
        save()
    }

    private func save() { state.saveDictionary(model.dictionary) }
}

// MARK: - Settings

struct SettingsView: View {
    let state: AppState
    @Bindable var model: WindowModel

    var body: some View {
        SectionHeader(title: "Settings", subtitle: "Saved to settings.json on this Mac.")
        Card {
            Picker("Dictation key", selection: Binding(get: { state.settings.dictationTrigger },
                                                       set: { value in state.update { $0.dictationTrigger = value } })) {
                Text("⌥ alone — hold, or double-tap for hands-free").tag(VoiceFlowCore.Settings.DictationTrigger.option)
                Text("\(state.settings.hotkey.displayName) — hold").tag(VoiceFlowCore.Settings.DictationTrigger.hotkeyCombination)
            }
            Divider()
            Picker("Paste into", selection: Binding(get: { state.settings.pasteInto },
                                                    set: { value in state.update { $0.pasteInto = value } })) {
                Text("The app in front when the text is ready").tag(InsertionPolicy.PasteTarget.currentApp)
                Text("Only the app where dictation started").tag(InsertionPolicy.PasteTarget.dictationApp)
            }
            Divider()
            Stepper(value: Binding(get: { state.settings.maxRecordingSeconds },
                                   set: { value in state.update { $0.maxRecordingSeconds = value } }), in: 30...600, step: 30) {
                Text("Longest dictation: \(Int(state.settings.maxRecordingSeconds / 60)) min \(Int(state.settings.maxRecordingSeconds) % 60) s")
            }
        }
        Card {
            Picker("Language", selection: Binding(get: { state.settings.language },
                                                  set: { value in state.update { $0.language = value } })) {
                ForEach(DictationLanguage.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            Picker("When Auto hears Hindi, write", selection: Binding(get: { state.settings.hindiScript },
                                                                     set: { value in state.update { $0.hindiScript = value } })) {
                Text("Devanagari (देवनागरी)").tag(HindiScript.devanagari)
                Text("Hinglish (Latin letters)").tag(HindiScript.hinglish)
            }
            .disabled(state.settings.language != .auto)
            Text("Switch language anytime with \(state.settings.languageHotkey.displayName). English words stay in Latin letters in Hindi. Prompt, Writing and Smart Rewrite work in English and German; Hindi and Hinglish use Clean.")
                .font(.callout).foregroundStyle(.secondary)
        }
        Card {
            Toggle("Show the floating pill while dictating", isOn: Binding(get: { state.settings.showIndicator },
                                                                          set: { on in state.update { $0.showIndicator = on } }))
            HStack {
                Text("Drag the pill anywhere; it stays where you leave it.").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Reset Position") { state.update { $0.indicatorPosition = nil } }
                    .disabled(state.settings.indicatorPosition == nil)
            }
        }
        Card {
            Picker("Keep the speech model loaded after dictating", selection: Binding(get: { state.settings.sttUnloadAfterSeconds },
                                                                                     set: { value in state.update { $0.sttUnloadAfterSeconds = value } })) {
                Text("Unload right away").tag(0.0)
                Text("30 seconds").tag(30.0)
                Text("1 minute (recommended)").tag(60.0)
                Text("5 minutes").tag(300.0)
                Text("15 minutes").tag(900.0)
            }
            Text("Loaded it uses about 1.2 GB; loading takes about 0.3 s and happens while you speak.").font(.callout).foregroundStyle(.secondary)
            Divider()
            Toggle("Use the developer vocabulary for recognition", isOn: Binding(get: { state.settings.useVocabularyPrompt },
                                                                                 set: { on in state.update { $0.useVocabularyPrompt = on } }))
        }
        Card {
            Toggle("Open at login", isOn: Binding(get: { model.openAtLogin }, set: { on in
                do { try LoginItem.setEnabled(on) } catch { Log.lifecycle.error("open at login: \(error.localizedDescription, privacy: .public)") }
                model.openAtLogin = LoginItem.isEnabled
            }))
            .onAppear { model.openAtLogin = LoginItem.isEnabled }
        }
    }
}

// MARK: - About

struct AboutView: View {
    let state: AppState
    @Bindable var model: WindowModel

    var body: some View {
        HStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: 4) {
                Text(BuildInfo.name).font(.largeTitle.weight(.semibold))
                Text("Version \(BuildInfo.version) (\(BuildInfo.build))").foregroundStyle(.secondary)
            }
        }
        Card {
            Label("Speech is recognized on this Mac (Whisper medium.en, Neural Engine).", systemImage: "cpu")
            Label("Text is rewritten only by Apple's on-device model, checked so it never changes what you said.", systemImage: "checkmark.shield")
            Label("No network, no accounts, no telemetry. Audio and transcripts are never saved.", systemImage: "lock")
        }
        Card {
            HStack {
                Button("Copy Diagnostics") {
                    let status = switch state.modelStatus {
                    case .installed: "installed"
                    case .missing: "not installed"
                    case .corrupted: "damaged"
                    case .incompatible: "incompatible"
                    }
                    copyToClipboard(Diagnostics.report(settings: state.settings, modelStatus: status, state: "\(state.pipelineState)"))
                    model.copiedNotice = "Copied (no transcripts included)"
                }
                Button("Open Data Folder") { NSWorkspace.shared.open(state.store.fileURL.deletingLastPathComponent()) }
                Button("Open settings.json") {
                    if !FileManager.default.fileExists(atPath: state.store.fileURL.path) { try? state.store.save(state.settings) }
                    NSWorkspace.shared.open(state.store.fileURL)
                }
            }
            if let notice = model.copiedNotice { Text(notice).font(.callout).foregroundStyle(.secondary) }
        }
    }
}
