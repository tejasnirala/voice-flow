/// Scores a Smart Mode rewrite of a transcript. The rewrite may fix punctuation and capitalization and remove fillers
/// and stutters, and turn spoken enumerations into lists (`ListScaffold`), but must not add content, drop content, or lose technical terms (spec §5, §12; rules 8–9).
public struct CleanupScore: Sendable {
    /// Runs of 2+ words in the output that aren't in the input, between words that are (answers, inventions).
    public var inventedPhrases: [String]
    /// Single output words not in the input (e.g. an added article).
    public var addedWords: Int
    /// Added words that aren't harmless grammar words ("deploy now" → "never deploy now"). A 2+ word run is also an
    /// invented phrase.
    public var addedContentWords: [String]
    /// Terms recognizable in the input that the output no longer contains.
    public var droppedTerms: [String]
    /// Input words deleted that are neither fillers, stutters (a repeated 1–4 word sequence), nor articles.
    public var droppedContentWords: [String]
    /// Articles ("a", "an", "the") and optional "that" removed: grammar edits, reported but not unsafe.
    public var droppedArticles: Int
    /// Input words replaced by different words ("should" → "must"): a meaning change.
    public var substitutedWords: [String]
    /// The output is much longer than the input (an answer, generated code or an elaboration rather than a rewrite).
    public var expanded: Bool
    /// Case/punctuation-sensitive token error rate against the ideal written reference, before and after the rewrite.
    public var formattingBefore: EditCounts
    public var formattingAfter: EditCounts
    /// Output word count ÷ input word count.
    public var lengthRatio: Double
    /// Output contains a Markdown code fence.
    public var hasCodeFence: Bool

    /// Violates the transform-only contract.
    public var isUnsafe: Bool {
        !inventedPhrases.isEmpty || !addedContentWords.isEmpty || !droppedTerms.isEmpty || !droppedContentWords.isEmpty
            || !substitutedWords.isEmpty
            || hasCodeFence || expanded
    }
}

public enum CleanupScorer {
    /// Fillers a cleanup is allowed to remove.
    public static let fillerWords: Set<String> = ["um", "uh", "er", "erm", "ah", "hmm", "mm", "like", "basically", "you", "know"]

    public static let articleWords: Set<String> = ["a", "an", "the"]
    /// Grammatically optional words a cleanup may delete (not replace): "the things that I need" → "the things I need".
    public static let optionalWords: Set<String> = ["that"]

    /// Whether the word at `index` belongs to a 1–4 word sequence immediately repeated ("when the when the").
    static func isStutter(_ tokens: [String], at index: Int) -> Bool {
        for n in 1...4 {
            for start in max(0, index - 2 * n + 1)...index where start + 2 * n <= tokens.count {
                if Array(tokens[start..<start + n]) == Array(tokens[start + n..<start + 2 * n]) { return true }
            }
        }
        return false
    }

    public static func score(input: String, output: String, reference: String, terms: [String]) -> CleanupScore {
        let (byTerm, variants) = AccuracyScorer.termVariants(terms)
        let inputTokens = TranscriptNormalizer.mergeTerms(TranscriptNormalizer.words(input), variants: variants)
        let (outputTokens, itemStarts) = ListScaffold.outputTokens(output, variants: variants)

        let inputSet = Set(inputTokens), outputSet = Set(outputTokens)
        let dropped = byTerm.filter { inputSet.contains($0.key) && !outputSet.contains($0.key) }.map(\.name)

        let ops = AccuracyScorer.alignment(reference: inputTokens, hypothesis: outputTokens)
        let scaffold = ListScaffold.removableInputIndices(input: inputTokens, ops: ops, itemStarts: itemStarts)
        var inputIndex = 0, outputIndex = 0
        var added = 0
        var addedContent: [String] = []
        func noteAdded(_ word: String) {
            added += 1
            if !RewriteGuard.insertableWords.contains(word) { addedContent.append(word) }
        }
        var articles = 0
        var droppedContent: [String] = []
        var substituted: [String] = []
        for op in ops {
            switch op {
            case .match:
                inputIndex += 1; outputIndex += 1
            case .substitution:
                // A filler or article may be removed, and an article may become another article; anything it turns into
                // otherwise counts as an added word.
                let word = inputTokens[inputIndex], replacement = outputTokens[outputIndex]
                if articleWords.contains(word), articleWords.contains(replacement) {
                    // "a" → "the"
                } else if fillerWords.contains(word) || articleWords.contains(word) {
                    noteAdded(replacement)
                } else {
                    substituted.append(word)
                }
                inputIndex += 1; outputIndex += 1
            case .deletion:
                let word = inputTokens[inputIndex]
                if fillerWords.contains(word) || isStutter(inputTokens, at: inputIndex) || scaffold.contains(inputIndex) {
                    // allowed cleanup
                } else if articleWords.contains(word) || optionalWords.contains(word) {
                    articles += 1
                } else {
                    droppedContent.append(word)
                }
                inputIndex += 1
            case .insertion:
                noteAdded(outputTokens[outputIndex])
                outputIndex += 1
            }
        }

        return CleanupScore(
            inventedPhrases: AccuracyScorer.insertedRuns(reference: inputTokens, hypothesis: outputTokens, minimumLength: 2),
            addedWords: added,
            addedContentWords: addedContent,
            droppedTerms: dropped,
            droppedContentWords: droppedContent,
            droppedArticles: articles,
            substitutedWords: substituted,
            expanded: Double(outputTokens.count) > Double(inputTokens.count) * 1.3 + 3,
            formattingBefore: AccuracyScorer.editCounts(reference: AccuracyScorer.formattedTokens(reference),
                                                        hypothesis: AccuracyScorer.formattedTokens(input)),
            formattingAfter: AccuracyScorer.editCounts(reference: AccuracyScorer.formattedTokens(reference),
                                                       hypothesis: AccuracyScorer.formattedTokens(output)),
            lengthRatio: inputTokens.isEmpty ? 0 : Double(outputTokens.count) / Double(inputTokens.count),
            hasCodeFence: output.contains("```")
        )
    }
}
