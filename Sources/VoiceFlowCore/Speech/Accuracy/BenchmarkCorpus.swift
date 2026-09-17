import Foundation

/// The developer-speech accuracy corpus (`benchmarks/corpus/developer-speech.json`).
public struct BenchmarkCorpus: Codable, Sendable {
    public var version: Int
    public var entries: [Entry]

    public enum Category: String, Codable, Sendable, CaseIterable {
        case normal, technical, identifiers, commands, files, architecture, natural, hinglish
    }

    public struct Entry: Codable, Sendable {
        public var id: String
        public var category: Category
        /// What the speaker says (also fed to TTS for synthetic clips).
        public var spoken: String
        /// The ideal written text.
        public var reference: String
        /// Canonical spellings of key terms that must be recognized (e.g. "PostgreSQL", "getUserById").
        public var terms: [String]
        /// False when TTS can't produce a meaningful clip (e.g. Hinglish); human recordings only.
        public var synthesizable: Bool

        public init(id: String, category: Category, spoken: String, reference: String, terms: [String], synthesizable: Bool = true) {
            self.id = id; self.category = category; self.spoken = spoken
            self.reference = reference; self.terms = terms; self.synthesizable = synthesizable
        }
    }

    public static func load(from url: URL) throws -> BenchmarkCorpus {
        try JSONDecoder().decode(BenchmarkCorpus.self, from: Data(contentsOf: url))
    }
}
