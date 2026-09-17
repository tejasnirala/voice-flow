/// Chooses the text mode from the app that receives the dictation (Phase 10, spec: per-app defaults).
/// Precedence: the owner's per-app choice → built-in rule (browser tab title, then bundle ID) → the menu's mode.
public enum AppModePolicy {
    public enum Source: String, Sendable, Equatable {
        case ownerRule = "owner rule"
        case builtIn = "built-in"
        case browserTab = "browser tab"
        case manual
    }

    public struct Resolution: Equatable, Sendable {
        public var mode: TextMode
        public var source: Source
    }

    public static let browsers: Set<String> = [
        "com.apple.Safari", "com.apple.SafariTechnologyPreview", "com.google.Chrome", "com.google.Chrome.canary",
        "company.thebrowser.Browser", "org.mozilla.firefox", "com.brave.Browser", "com.microsoft.edgemac", "com.operasoftware.Opera",
        "com.vivaldi.Vivaldi", "app.zen-browser.zen",
    ]

    /// Built-in defaults by bundle ID.
    public static let builtIn: [String: TextMode] = {
        var table: [String: TextMode] = [:]
        let developer = ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.todesktop.230313mzl4w4u92", "dev.zed.Zed",
                         "com.apple.dt.Xcode", "com.sublimetext.4", "com.exafunction.windsurf", "com.vscodium",
                         // Terminals: Developer rather than Code, since prose to CLI agents is common there (Code is a choice).
                         "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "com.mitchellh.ghostty",
                         "net.kovidgoyal.kitty", "org.alacritty", "io.alacritty"]
        let clean = ["com.tinyspeck.slackmacgap", "com.hnc.Discord", "net.whatsapp.WhatsApp", "desktop.WhatsApp",
                     "com.apple.MobileSMS", "ru.keepcoder.Telegram", "com.microsoft.teams2", "com.apple.mail",
                     "com.microsoft.Outlook", "us.zoom.xos"]
        let prompt = ["com.openai.chat", "com.anthropic.claudefordesktop", "com.google.GeminiMacOS", "ai.perplexity.mac"]
        let writing = ["com.apple.Notes", "notion.id", "md.obsidian", "com.apple.iWork.Pages", "com.microsoft.Word",
                       "com.apple.TextEdit", "net.shinyfrog.bear", "com.ulyssesapp.mac"]
        for id in developer { table[id] = .developer }
        for id in clean + Array(browsers) { table[id] = .clean }
        for id in prompt { table[id] = .prompt }
        for id in writing { table[id] = .writing }
        return table
    }()

    /// Bundle-ID prefixes (JetBrains IDEs share one).
    static let builtInPrefixes: [(String, TextMode)] = [("com.jetbrains.", .developer), ("com.google.android.studio", .developer)]

    /// Browser window titles that mean an AI assistant tab.
    static let assistantTitleMarkers = ["chatgpt", "claude", "gemini", "perplexity", "copilot", "deepseek", "mistral le chat", "grok"]

    public static func resolve(bundleID: String?, windowTitle: String?, settings: Settings) -> Resolution {
        let manual = Resolution(mode: settings.textMode, source: .manual)
        guard settings.modeByApp, let bundleID else { return manual }
        if let mode = settings.appModes[bundleID] { return Resolution(mode: mode, source: .ownerRule) }
        if browsers.contains(bundleID), let title = windowTitle?.lowercased(),
           assistantTitleMarkers.contains(where: { title.contains($0) }) {
            return Resolution(mode: .prompt, source: .browserTab)
        }
        if let mode = builtInMode(for: bundleID) { return Resolution(mode: mode, source: .builtIn) }
        return manual
    }

    public static func builtInMode(for bundleID: String) -> TextMode? {
        builtIn[bundleID] ?? builtInPrefixes.first { bundleID.hasPrefix($0.0) }?.1
    }
}
