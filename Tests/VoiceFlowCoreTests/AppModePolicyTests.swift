import Foundation
import Testing
@testable import VoiceFlowCore

@Suite struct AppModePolicyTests {
    var settings = Settings.default

    @Test(arguments: [
        ("com.microsoft.VSCode", TextMode.developer), ("com.apple.Terminal", .developer), ("com.jetbrains.intellij", .developer),
        ("com.tinyspeck.slackmacgap", .clean), ("com.apple.Safari", .clean), ("com.openai.chat", .prompt),
        ("com.apple.Notes", .writing), ("notion.id", .writing),
    ])
    func builtInDefaults(bundleID: String, mode: TextMode) {
        #expect(AppModePolicy.resolve(bundleID: bundleID, windowTitle: nil, settings: settings)
                == .init(mode: mode, source: .builtIn))
    }

    @Test func assistantTabInABrowserIsPrompt() {
        #expect(AppModePolicy.resolve(bundleID: "com.google.Chrome", windowTitle: "ChatGPT - Google Chrome", settings: settings)
                == .init(mode: .prompt, source: .browserTab))
        #expect(AppModePolicy.resolve(bundleID: "com.google.Chrome", windowTitle: "Inbox - Gmail", settings: settings).mode == .clean)
        // Titles only matter in browsers.
        #expect(AppModePolicy.resolve(bundleID: "com.microsoft.VSCode", windowTitle: "claude.ts", settings: settings).mode == .developer)
    }

    @Test func ownerRuleWinsAndUnknownAppsUseTheMenuMode() {
        var s = settings
        s.textMode = .writing
        s.appModes = ["com.apple.Terminal": .code, "com.google.Chrome": .writing]
        #expect(AppModePolicy.resolve(bundleID: "com.apple.Terminal", windowTitle: nil, settings: s) == .init(mode: .code, source: .ownerRule))
        #expect(AppModePolicy.resolve(bundleID: "com.google.Chrome", windowTitle: "ChatGPT", settings: s).mode == .writing)
        #expect(AppModePolicy.resolve(bundleID: "com.example.unknown", windowTitle: nil, settings: s) == .init(mode: .writing, source: .manual))
        #expect(AppModePolicy.resolve(bundleID: nil, windowTitle: nil, settings: s).source == .manual)
    }

    @Test func turnedOffAlwaysUsesTheMenuMode() {
        var s = settings
        s.modeByApp = false
        s.appModes = ["com.apple.Terminal": .code]
        #expect(AppModePolicy.resolve(bundleID: "com.apple.Terminal", windowTitle: nil, settings: s) == .init(mode: .clean, source: .manual))
    }

    @Test func settingsDecodeAppModesTolerantly() throws {
        let json = #"{"modeByApp": false, "appModes": {"com.apple.Terminal": "code", "com.x": "poetry"}}"#
        let s = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
        #expect(!s.modeByApp)
        #expect(s.appModes == ["com.apple.Terminal": .code])
        #expect(Settings.default.modeByApp)
        let roundTrip = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(s))
        #expect(roundTrip == s)
    }
}
