/// Checks an LLM rewrite against the text it was given, without any reference. A rewrite is accepted only if it adds no
/// phrases, drops or replaces no content words, keeps every recognizable developer term, doesn't grow into an answer or
/// code, and contains no code fence. Otherwise the pipeline uses the un-rewritten text (never loses speech, never pastes
/// an answer). Measured: turns every candidate model's unsafe outputs into safe fallbacks (docs/ACCURACY.md §6).
public enum RewriteGuard {
    public enum Verdict: Equatable, Sendable {
        case accept
        case reject(reasons: [String])
    }

    /// - Parameter terms: developer vocabulary (e.g. "Next.js", "PostgreSQL") that must survive if present in `input`.
    public static func evaluate(input: String, output: String, terms: [String]) -> Verdict {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .reject(reasons: ["empty output"]) }
        let s = CleanupScorer.score(input: input, output: trimmed, reference: trimmed, terms: terms)
        var reasons: [String] = []
        if !s.inventedPhrases.isEmpty { reasons.append("added words") }
        if !s.droppedContentWords.isEmpty { reasons.append("dropped words") }
        if !s.substitutedWords.isEmpty { reasons.append("replaced words") }
        if !s.droppedTerms.isEmpty { reasons.append("dropped developer terms") }
        if s.expanded { reasons.append("output much longer than input") }
        if s.hasCodeFence { reasons.append("code block") }
        return reasons.isEmpty ? .accept : .reject(reasons: reasons)
    }

    /// Splits the bundled developer vocabulary ("Next.js, React, …") into terms.
    public static func terms(fromVocabulary vocabulary: String?) -> [String] {
        (vocabulary ?? "").split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
