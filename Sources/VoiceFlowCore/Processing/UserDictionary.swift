import Foundation

/// The owner's own vocabulary (`dictionary.json` next to settings.json). Local, optional, editable in any text editor.
/// - `terms`: spellings to keep ("Supabase", "tRPC"). Added to the speech-recognition prompt, protected by the rewrite
///   guards, and their casing restored in every mode except Raw.
/// - `replacements`: explicit spoken → written pairs ("kube control" → "kubectl"), whole words, case-insensitive, applied in
///   every mode except Raw. Only what the owner wrote down is replaced.
public struct UserDictionary: Codable, Equatable, Sendable {
    public struct Replacement: Codable, Equatable, Sendable {
        public var spoken: String
        public var written: String
        public init(spoken: String, written: String) { self.spoken = spoken; self.written = written }
    }

    public var terms: [String]
    public var replacements: [Replacement]

    public static let empty = UserDictionary(terms: [], replacements: [])
    /// Terms beyond this aren't added to the speech prompt (Whisper's prompt window is limited).
    public static let maxPromptTerms = 40

    public init(terms: [String], replacements: [Replacement]) {
        self.terms = terms
        self.replacements = replacements
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        terms = ((try? c.decodeIfPresent([String].self, forKey: .terms)) ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        replacements = ((try? c.decodeIfPresent([Replacement].self, forKey: .replacements)) ?? [])
            .filter { !$0.spoken.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    public var isEmpty: Bool { terms.isEmpty && replacements.isEmpty }

    /// Terms the rewrite guards must keep.
    public var protectedTerms: [String] { terms + replacements.map(\.written) }

    /// The speech-recognition prompt: the bundled vocabulary plus the owner's terms.
    public func speechPrompt(base: String?) -> String? {
        let extra = terms.prefix(Self.maxPromptTerms).joined(separator: ", ")
        guard !extra.isEmpty else { return base }
        guard let base, !base.isEmpty else { return extra }
        return base + ", " + extra
    }

    /// Applies replacements, then term casing, line by line (line breaks and list markers kept).
    public func apply(to text: String) -> String {
        guard !isEmpty else { return text }
        var rules: [([String], String)] = replacements.map { (Self.words($0.spoken), $0.written) }
        rules += terms.map { (Self.words($0), $0) }
        rules = rules.filter { !$0.0.isEmpty }.sorted { $0.0.count > $1.0.count }
        return text.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            var t = line.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
            var i = 0
            outer: while i < t.count {
                for (spoken, written) in rules where i + spoken.count <= t.count {
                    let run = t[i..<i + spoken.count].map(DeveloperFormatter.split)
                    guard run.dropLast().allSatisfy({ $0.2.isEmpty }), run.dropFirst().allSatisfy({ $0.0.isEmpty }),
                          run.map({ $0.1.lowercased() }) == spoken else { continue }
                    t.replaceSubrange(i..<i + spoken.count, with: [run.first!.0 + written + run.last!.2])
                    i += 1
                    continue outer
                }
                i += 1
            }
            return t.joined(separator: " ")
        }.joined(separator: "\n")
    }

    static func words(_ phrase: String) -> [String] {
        phrase.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
    }

    // MARK: Storage

    public static func fileURL(in directory: URL) -> URL { directory.appendingPathComponent("dictionary.json") }

    /// Missing or unreadable files give an empty dictionary (never an error that blocks dictation).
    public static func load(from url: URL) -> UserDictionary {
        guard let data = try? Data(contentsOf: url), let dictionary = try? JSONDecoder().decode(UserDictionary.self, from: data) else {
            return .empty
        }
        return dictionary
    }

    /// A starter file for the owner to edit.
    public static let template = """
    {
      "terms": [],
      "replacements": [
        { "spoken": "voice flow", "written": "VoiceFlow" }
      ]
    }

    """
}
