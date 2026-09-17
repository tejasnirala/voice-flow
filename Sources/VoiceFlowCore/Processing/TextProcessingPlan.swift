import Foundation

/// The deterministic part of turning a raw STT transcript into the text that gets pasted, per text mode.
public enum TextProcessingPlan {
    /// Applied before any optional model rewrite (after Whisper artifact removal):
    /// Raw → unchanged; Clean, Prompt, Writing → rule-based cleanup; Developer → cleanup + spoken symbols, developer
    /// corrections and term casing; Code → hesitations/stutters removed + code symbols. The owner's dictionary is applied
    /// last in every mode except Raw.
    public static func prepare(_ transcript: String, mode: TextMode, dictionary: UserDictionary = .empty) -> String {
        switch mode {
        case .raw: transcript
        case .clean, .prompt, .writing: dictionary.apply(to: RuleBasedCleanup.clean(transcript))
        case .developer: dictionary.apply(to: DeveloperFormatter.format(RuleBasedCleanup.clean(transcript)))
        case .code: dictionary.apply(to: CodeFormatter.format(RuleBasedCleanup.clean(transcript, sentenceCase: false)))
        }
    }

    /// Chooses between a model rewrite and the prepared text using the mode's guard policy.
    /// Developer output is re-formatted so the model can't undo symbol joins or term casing.
    public static func finalText(prepared: String, rewrite: String?, terms: [String], mode: TextMode = .clean,
                                 dictionary: UserDictionary = .empty)
        -> (text: String, verdict: RewriteGuard.Verdict?) {
        guard let rewrite else { return (prepared, nil) }
        let verdict = RewriteGuard.evaluate(input: prepared, output: rewrite, terms: terms, policy: mode.guardPolicy)
        switch verdict {
        case .accept:
            let text = restoreApostrophes(from: prepared, in: tidy(rewrite, keepParagraphs: mode.guardPolicy == .contentPreserving))
            return (dictionary.apply(to: mode == .developer ? DeveloperFormatter.format(text) : text), verdict)
        case .reject:
            return (prepared, verdict)
        }
    }

    /// Layout-only fixes to an accepted rewrite: trailing spaces on lines, runs of blank lines, and a lone "- " bullet.
    /// Without `keepParagraphs` (Clean, Developer), line breaks survive only around list items.
    static func tidy(_ text: String, keepParagraphs: Bool = true) -> String {
        guard keepParagraphs else {
            var out: [String] = []
            for line in tidy(text).split(separator: "\n").map({ $0.trimmingCharacters(in: .whitespaces) }) where !line.isEmpty {
                if let last = out.last, !isListItem(line), !isListItem(last) {
                    out[out.count - 1] = last + " " + line
                } else {
                    out.append(line)
                }
            }
            let joined = out.joined(separator: "\n")
            return out.count == 1 && joined.hasPrefix("- ") ? String(joined.dropFirst(2)) : joined
        }
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            String(line.reversed().drop { $0 == " " || $0 == "\t" }.reversed())
        }
        lines = lines.enumerated().filter { $0.offset == 0 || !($0.element.isEmpty && lines[$0.offset - 1].isEmpty) }.map(\.element)
        let joined = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let nonEmpty = joined.split(separator: "\n")
        if nonEmpty.count == 1, joined.hasPrefix("- ") { return String(joined.dropFirst(2)) }
        return joined
    }

    static func isListItem(_ line: String) -> Bool { ["- ", "* ", "• "].contains { line.hasPrefix($0) } }

    /// Word boundaries without touching apostrophes ("users'" keeps its mark).
    static let edgePunctuation = CharacterSet(charactersIn: ".,;:!?\"()[]{}“”«»-–—*")

    /// A rewrite may not lose an apostrophe the transcript had ("Apple's" → "Apples", "it's" → "its"): the guard can't see
    /// apostrophes, so the transcript's spelling is restored for every word that matches it letter for letter. Words the
    /// transcript also wrote without an apostrophe are left as the rewrite has them.
    static func restoreApostrophes(from prepared: String, in text: String) -> String {
        func key(_ core: Substring) -> String { String(core.lowercased().filter { $0.isLetter || $0.isNumber }) }
        func core(_ token: Substring) -> (lead: Substring, core: Substring, trail: Substring) {
            let start = token.firstIndex { !$0.unicodeScalars.allSatisfy(edgePunctuation.contains) } ?? token.endIndex
            let end = token[start...].lastIndex { !$0.unicodeScalars.allSatisfy(edgePunctuation.contains) }.map(token.index(after:)) ?? start
            return (token[..<start], token[start..<end], token[end...])
        }
        var marked: [String: Substring] = [:]
        var ambiguous = Set<String>()
        for token in prepared.split(whereSeparator: \.isWhitespace) {
            let c = core(token).core
            let k = key(c)
            guard !k.isEmpty else { continue }
            if c.contains("'") || c.contains("’") {
                if let existing = marked[k], existing.lowercased() != c.lowercased() { ambiguous.insert(k) }
                marked[k] = c
            } else {
                ambiguous.insert(k)
            }
        }
        guard !marked.isEmpty else { return text }
        return text.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            line.split(separator: " ", omittingEmptySubsequences: false).map { token -> String in
                let (lead, c, trail) = core(token)
                let k = key(c)
                guard !c.contains("'"), !c.contains("’"), !ambiguous.contains(k), var original = marked[k].map(String.init) else {
                    return String(token)
                }
                if let first = c.first, first.isUppercase { original = original.prefix(1).uppercased() + original.dropFirst() }
                return lead + original + trail
            }.joined(separator: " ")
        }.joined(separator: "\n")
    }
}
