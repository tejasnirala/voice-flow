import Foundation

/// Loads and saves `Settings` as JSON in a directory (Application Support in the app, a temp dir in tests).
///
/// Never throws on load: a missing file yields defaults, and an unreadable file is moved aside to
/// `settings.invalid.json` (so the user's edits aren't silently destroyed) before falling back to defaults.
public struct SettingsStore: Sendable {
    public enum LoadOutcome: Equatable, Sendable {
        case loaded
        case missingUsedDefaults
        /// The file couldn't be decoded. It was preserved at the given path and defaults were used.
        case invalidUsedDefaults(preservedAt: String)
    }

    public let fileURL: URL

    public init(directory: URL) {
        fileURL = directory.appendingPathComponent("settings.json")
    }

    /// `~/Library/Application Support/VoiceFlow`
    public static func applicationSupportDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VoiceFlow", isDirectory: true)
    }

    public func load() -> (settings: Settings, outcome: LoadOutcome) {
        guard let data = try? Data(contentsOf: fileURL) else {
            return (.default, .missingUsedDefaults)
        }
        if let settings = try? JSONDecoder().decode(Settings.self, from: data) {
            return (settings, .loaded)
        }
        let preserved = fileURL.deletingLastPathComponent().appendingPathComponent("settings.invalid.json")
        try? FileManager.default.removeItem(at: preserved)
        try? FileManager.default.moveItem(at: fileURL, to: preserved)
        return (.default, .invalidUsedDefaults(preservedAt: preserved.path))
    }

    /// Writes atomically, creating the directory if needed.
    public func save(_ settings: Settings) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(settings).write(to: fileURL, options: .atomic)
    }
}
