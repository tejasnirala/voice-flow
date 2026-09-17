/// Checks an LLM rewrite against the text it was given, without any reference. A rewrite is accepted only if it adds no
/// phrases, drops or replaces no content words, keeps every recognizable developer term, doesn't grow into an answer or
/// code, and contains no code fence. Otherwise the pipeline uses the un-rewritten text (never loses speech, never pastes
/// an answer). Measured: turns every candidate model's unsafe outputs into safe fallbacks (docs/ACCURACY.md §6).
public enum RewriteGuard {
    public enum Verdict: Equatable, Sendable {
        case accept
        case reject(reasons: [String])
    }

    public enum Policy: Sendable {
        /// Word-for-word: only punctuation, case, fillers, stutters and articles may change (Clean, Developer).
        case strict
        /// Same content words in the same order: grammar words ("the", "we", "so", …) may be dropped and a few ("the", "is",
        /// "to", …) added, and sentences split, joined or bulleted; no content word may be added, dropped, replaced or moved
        /// (Prompt, Writing).
        case contentPreserving
    }

    /// Grammar words a content-preserving rewrite may drop ("we move" → "Move", "so the plan" → "The plan"). Everything
    /// else is content, including words that change logic or meaning when swapped: negations, connectives (but, or, if,
    /// when, because), modals (should, can, must), quantifiers (all, some), question words, "from", and time words.
    static let functionWords: Set<String> = [
        "a", "an", "the", "is", "are", "was", "were", "be", "been", "being", "am", "do", "does", "did", "have", "has", "had",
        "to", "of", "in", "on", "at", "for", "with", "by", "into", "onto", "about", "as", "so", "and", "then", "that", "this",
        "these", "those", "which", "it", "its", "there", "here", "also", "just", "please", "i", "me", "my", "we", "us", "our",
        "you", "your", "they", "them", "their", "let", "s", "up", "out", "too", "very", "really", "actually", "okay", "well",
    ]

    /// The subset of grammar words a rewrite may add when absent from the input (sentence splitting and grammar only).
    /// Pronouns aren't here: "I will review" → "We will review" is a meaning change.
    static let insertableWords: Set<String> = [
        "a", "an", "the", "is", "are", "was", "were", "be", "to", "of", "in", "on", "for", "with", "as", "and", "then", "that",
        "this", "it", "its", "there", "also",
    ]

    /// - Parameter terms: developer vocabulary (e.g. "Next.js", "PostgreSQL") that must survive if present in `input`.
    public static func evaluate(input: String, output: String, terms: [String], policy: Policy = .strict) -> Verdict {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .reject(reasons: ["empty output"]) }
        if policy == .contentPreserving { return evaluateContent(input: input, output: trimmed, terms: terms) }
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

    static func evaluateContent(input: String, output: String, terms: [String]) -> Verdict {
        let s = CleanupScorer.score(input: input, output: output, reference: output, terms: terms)
        let (_, variants) = AccuracyScorer.termVariants(terms)
        /// Content words in order of first appearance (repeats allowed: "uses Azure. The team uses GCP.").
        func content(_ text: String) -> [String] {
            var seen = Set<String>()
            return TranscriptNormalizer.mergeTerms(TranscriptNormalizer.words(text), variants: variants)
                .filter { !functionWords.contains($0) && !CleanupScorer.fillerWords.contains($0) && seen.insert($0).inserted }
        }
        let inputContent = content(input), outputContent = content(output)
        let inputSet = Set(inputContent), outputSet = Set(outputContent)
        let inputWords = Set(TranscriptNormalizer.words(input))
        let addedGrammar = Set(TranscriptNormalizer.words(output)).subtracting(inputWords)
            .filter { functionWords.contains($0) && !insertableWords.contains($0) }
        var reasons: [String] = []
        if !outputSet.subtracting(inputSet).isEmpty || !addedGrammar.isEmpty { reasons.append("added words") }
        if !inputSet.subtracting(outputSet).isEmpty { reasons.append("dropped words") }
        // Same words in a different order can swap meaning ("from PostgreSQL to Redis" → "from Redis to PostgreSQL").
        if inputSet == outputSet, inputContent != outputContent { reasons.append("reordered words") }
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
