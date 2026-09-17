import Foundation
import Testing
@testable import VoiceFlowCore

@Suite struct SettingsTests {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("VoiceFlowTests-\(UUID().uuidString)", isDirectory: true)

    @Test func defaultsAreFastModeOptionSpace() {
        #expect(Settings.default.processingMode == .fast)
        #expect(Settings.default.hotkey == Settings.Hotkey(keyCode: 49, carbonModifiers: 0x0800))
        #expect(Settings.default.maxRecordingSeconds == 120)
        #expect(Settings.default.saveRecordingsForDebugging == false)
    }

    @Test func hotkeyDisplayNames() {
        #expect(Settings.Hotkey.optionSpace.displayName == "⌥Space")
        #expect(Settings.Hotkey(keyCode: 49, carbonModifiers: 0x0100 | 0x0200).displayName == "⇧⌘Space")
        #expect(Settings.Hotkey(keyCode: 3, carbonModifiers: 0x1000).displayName == "⌃Key 3")
    }

    @Test func missingFileYieldsDefaults() {
        let (settings, outcome) = SettingsStore(directory: directory).load()
        #expect(settings == .default)
        #expect(outcome == .missingUsedDefaults)
    }

    @Test func saveThenLoadRoundTrips() throws {
        let store = SettingsStore(directory: directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        var settings = Settings.default
        settings.processingMode = .smart
        settings.maxRecordingSeconds = 45
        try store.save(settings)
        let (loaded, outcome) = store.load()
        #expect(loaded == settings)
        #expect(outcome == .loaded)
    }

    @Test func missingKeysTakeDefaultsAndUnknownKeysAreIgnored() throws {
        let json = #"{"processingMode":"smart","someFutureSetting":true}"#
        let settings = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
        #expect(settings.processingMode == .smart)
        #expect(settings.hotkey == .optionSpace)
        #expect(settings.maxRecordingSeconds == 120)
    }

    @Test func invalidValuesFallBackPerKey() throws {
        let json = #"{"processingMode":"turbo","maxRecordingSeconds":-5}"#
        let settings = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
        #expect(settings == .default)
    }

    @Test func corruptFileIsPreservedAndDefaultsUsed() throws {
        let store = SettingsStore(directory: directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: store.fileURL)

        let (settings, outcome) = store.load()
        #expect(settings == .default)
        let preserved = directory.appendingPathComponent("settings.invalid.json")
        #expect(outcome == .invalidUsedDefaults(preservedAt: preserved.path))
        #expect(try String(contentsOf: preserved, encoding: .utf8) == "{ not json")
        #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))
    }
}
