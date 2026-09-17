/// Spoken enumeration words a rewrite may remove when it turns them into a list:
/// "there are two things, one which is local testing, the second point will be fixing bugs" →
/// "There are two things:\n- Local testing\n- Fixing bugs". Only a run of these words that ends exactly where a list item
/// begins, and that contains a counting word, is removable; everything else is scored as usual.
public enum ListScaffold {
    /// Counting words (number words are digits after normalization: "one" → "1").
    static let markers: Set<String> = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "first", "firstly", "second",
                                       "secondly", "third", "thirdly", "fourth", "fifth", "last", "lastly", "finally",
                                       "next", "another"]
    /// Words that may accompany a counting word in the removed run ("the second point will be to").
    static let companions: Set<String> = ["point", "points", "thing", "things", "item", "items", "bullet", "step", "steps",
                                          "number", "part", "the", "a", "an", "is", "are", "will", "would", "be", "to",
                                          "which", "that", "and", "then", "also", "it", "this", "of"]
    static let maxRunLength = 8

    /// Normalized output tokens (per line, terms merged) and the token indices where list items ("- ", "* ", "• ") start.
    public static func outputTokens(_ output: String, variants: [String: String]) -> (tokens: [String], itemStarts: Set<Int>) {
        var tokens: [String] = []
        var starts: [Int] = []
        for line in output.split(separator: "\n") {
            let trimmed = line.drop { $0 == " " || $0 == "\t" }
            let lineTokens = TranscriptNormalizer.mergeTerms(TranscriptNormalizer.words(String(line)), variants: variants)
            if ["- ", "* ", "• "].contains(where: { trimmed.hasPrefix($0) }), !lineTokens.isEmpty { starts.append(tokens.count) }
            tokens += lineTokens
        }
        return (tokens, starts.count >= 2 ? Set(starts) : [])
    }

    /// Input token indices deleted by `ops` that are enumeration scaffolding in front of a list item.
    public static func removableInputIndices(input: [String], ops: [AccuracyScorer.AlignmentOp], itemStarts: Set<Int>) -> Set<Int> {
        guard !itemStarts.isEmpty else { return [] }
        var removable = Set<Int>()
        var run: [Int] = []
        var i = 0, j = 0
        for op in ops {
            switch op {
            case .deletion:
                run.append(i); i += 1
            case .match, .substitution:
                if op == .match, itemStarts.contains(j), !run.isEmpty, run.count <= maxRunLength,
                   run.allSatisfy({ markers.contains(input[$0]) || companions.contains(input[$0]) || input[$0] == "other" }),
                   run.contains(where: { markers.contains(input[$0]) }) || isOtherPhrase(run.map { input[$0] }) {
                    removable.formUnion(run)
                }
                run = []; i += 1; j += 1
            case .insertion:
                run = []; j += 1
            }
        }
        return removable
    }

    /// "the other is" / "the other one will be": "other" counts only when directly followed by a linking verb, so
    /// "the other service is down" keeps "other".
    static func isOtherPhrase(_ words: [String]) -> Bool {
        guard let index = words.firstIndex(of: "other") else { return false }
        let rest = words[(index + 1)...].drop { $0 == "1" }
        return ["is", "are", "will", "would"].contains(rest.first ?? "")
    }
}
