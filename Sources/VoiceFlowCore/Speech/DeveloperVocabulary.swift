import Foundation

public enum DeveloperVocabulary {
    /// The developer vocabulary bundled with the app (Resources/developer-vocabulary.txt), used as Whisper's initial
    /// prompt. Falls back to the source tree when running unbundled (`swift run`).
    public static func prompt(bundle: Bundle = .main) -> String? {
        let bundled = bundle.url(forResource: "developer-vocabulary", withExtension: "txt")
        let source = URL(fileURLWithPath: #filePath)   // Sources/VoiceFlowCore/Speech/DeveloperVocabulary.swift
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/developer-vocabulary.txt")
        guard let url = bundled ?? (FileManager.default.fileExists(atPath: source.path) ? source : nil),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
