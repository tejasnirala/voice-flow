import Foundation

/// A rewrite prompt from `prompts/<mode>.json`: system rules plus few-shot examples.
public struct RewritePrompt: Codable, Equatable, Sendable {
    public struct Example: Codable, Equatable, Sendable {
        public var input: String
        public var output: String
    }

    public var version: Int
    public var mode: String
    public var system: String
    public var examples: [Example]

    public static func load(from url: URL) throws -> RewritePrompt {
        try JSONDecoder().decode(RewritePrompt.self, from: Data(contentsOf: url))
    }

    /// Instructions for a model that takes one instruction string (examples appended in a fixed format).
    public var instructions: String {
        system + "\n\nExamples:\n" + examples.map { "Transcript: \($0.input)\nRewritten: \($0.output)" }.joined(separator: "\n\n")
    }

    /// The bundled prompt for `mode` (Contents/Resources/prompts), falling back to the source tree when unbundled.
    public static func bundled(_ mode: String, bundle: Bundle = .main) -> RewritePrompt? {
        let source = URL(fileURLWithPath: #filePath)   // Sources/VoiceFlowCore/Processing/RewritePrompt.swift
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("prompts/\(mode).json")
        let url = bundle.url(forResource: mode, withExtension: "json", subdirectory: "prompts") ?? source
        return try? load(from: url)
    }
}
