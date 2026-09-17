/// Edit-distance counts for one reference/hypothesis pair.
public struct EditCounts: Sendable, Equatable {
    public var substitutions = 0, deletions = 0, insertions = 0, referenceWords = 0
    public var errors: Int { substitutions + deletions + insertions }

    public init(substitutions: Int = 0, deletions: Int = 0, insertions: Int = 0, referenceWords: Int = 0) {
        self.substitutions = substitutions; self.deletions = deletions
        self.insertions = insertions; self.referenceWords = referenceWords
    }

    public static func + (a: EditCounts, b: EditCounts) -> EditCounts {
        EditCounts(substitutions: a.substitutions + b.substitutions, deletions: a.deletions + b.deletions,
                   insertions: a.insertions + b.insertions, referenceWords: a.referenceWords + b.referenceWords)
    }

    /// Word error rate; 0 when the reference is empty.
    public var rate: Double { referenceWords == 0 ? 0 : Double(errors) / Double(referenceWords) }
}

public struct EntryScore: Sendable {
    /// Spelling-agnostic WER (terms merged, punctuation and case ignored).
    public var words: EditCounts
    /// Case- and punctuation-sensitive token WER: a proxy for punctuation/capitalization quality.
    public var formatted: EditCounts
    /// Terms the engine heard correctly, in any spelling.
    public var recognizedTerms: [String]
    public var missedTerms: [String]
    /// Terms that appear with their exact canonical spelling in the raw output.
    public var exactTerms: [String]
}

public enum AccuracyScorer {
    /// Scores one transcript.
    ///
    /// - `spoken`: the words actually said; the reference for word accuracy (WER).
    /// - `reference`: the ideal written text; the reference for formatting quality.
    /// - `terms`: `canonical` or `canonical|spoken variant|…` (e.g. `kubectl get pods|kube control get pods`).
    ///   Any variant counts as recognized; only the canonical spelling counts as exact.
    ///
    /// WER merges a term into one token only when the hypothesis recognized it, so a correctly heard
    /// `getUserById` isn't penalized for its spelling, while a misheard one is scored word by word
    /// instead of inflating errors against a single merged reference token. Spoken separator words
    /// ("dot", "slash", …) are excluded from WER; term recognition covers them.
    public static func score(reference: String, spoken: String, hypothesis: String, terms: [String]) -> EntryScore {
        var variantsByTerm: [(name: String, key: String, variants: [String: String])] = []
        var allVariants: [String: String] = [:]
        for term in terms {
            let parts = term.split(separator: "|").map { String($0) }
            let key = TranscriptNormalizer.key(parts[0])
            var variants: [String: String] = [:]
            for part in parts { variants[TranscriptNormalizer.key(part)] = key }
            variantsByTerm.append((parts[0], key, variants))
            allVariants.merge(variants) { a, _ in a }
        }
        let hypWords = TranscriptNormalizer.words(hypothesis)
        let hypAllMerged = Set(TranscriptNormalizer.mergeTerms(hypWords, variants: allVariants))
        let recognized = variantsByTerm.filter { hypAllMerged.contains($0.key) }

        var recognizedVariants: [String: String] = [:]
        for t in recognized { recognizedVariants.merge(t.variants) { a, _ in a } }
        let forWER: ([String]) -> [String] = { tokens in
            TranscriptNormalizer.mergeTerms(tokens, variants: recognizedVariants)
                .filter { !TranscriptNormalizer.separatorWords.contains($0) }
        }
        let recognizedKeys = Set(recognized.map(\.key))

        return EntryScore(
            words: editCounts(reference: forWER(TranscriptNormalizer.words(spoken)), hypothesis: forWER(hypWords)),
            formatted: editCounts(reference: formattedTokens(reference), hypothesis: formattedTokens(hypothesis)),
            recognizedTerms: recognized.map(\.name),
            missedTerms: variantsByTerm.filter { !recognizedKeys.contains($0.key) }.map(\.name),
            exactTerms: variantsByTerm.filter { hypothesis.contains($0.name) }.map(\.name)
        )
    }

    static func formattedTokens(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Levenshtein alignment over tokens (two-row DP, tracking operation counts).
    public static func editCounts(reference: [String], hypothesis: [String]) -> EditCounts {
        typealias Cell = (cost: Int, s: Int, d: Int, i: Int)
        var prev: [Cell] = (0...hypothesis.count).map { ($0, 0, 0, $0) }
        for r in reference {
            var cur: [Cell] = [(prev[0].cost + 1, prev[0].s, prev[0].d + 1, prev[0].i)]
            for (j, h) in hypothesis.enumerated() {
                let diag = prev[j]
                let sub: Cell = r == h ? diag : (diag.cost + 1, diag.s + 1, diag.d, diag.i)
                let del: Cell = (prev[j + 1].cost + 1, prev[j + 1].s, prev[j + 1].d + 1, prev[j + 1].i)
                let ins: Cell = (cur[j].cost + 1, cur[j].s, cur[j].d, cur[j].i + 1)
                cur.append([sub, del, ins].min { $0.cost < $1.cost }!)
            }
            prev = cur
        }
        let end = prev[hypothesis.count]
        return EditCounts(substitutions: end.s, deletions: end.d, insertions: end.i, referenceWords: reference.count)
    }
}
