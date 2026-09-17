import Foundation

/// Deterministic transcript cleanup (no LLM): removes hesitation sounds and stutters, capitalizes the first word and
/// adds missing end punctuation. It only deletes fillers or exact repeats and changes case or punctuation, so it can't
/// add, drop or change meaning (verified with `CleanupScorer`: docs/ACCURACY.md §6).
public enum RuleBasedCleanup {
    /// Hesitation sounds, never meaningful in dictation. Ambiguous words ("like", "so", "you know") are kept.
    static let hesitations: Set<String> = ["um", "uh", "er", "erm", "ah", "hmm", "mm", "uhm", "umm", "uhh"]
    /// Single words commonly stuttered; a doubled single word is collapsed only for these ("bye bye" stays).
    static let stutterWords: Set<String> = ["the", "a", "an", "to", "is", "it", "i", "we", "and", "of", "in", "that", "this",
                                            "for", "on", "with", "was", "be", "you", "they", "he", "she", "my", "our", "if", "so"]
    /// Lowercase tools and commands that must not be capitalized at the start of a sentence.
    static let keepLowercase: Set<String> = ["npm", "npx", "pnpm", "yarn", "git", "kubectl", "curl", "wget", "ssh", "sudo",
                                             "cd", "ls", "cat", "grep", "vim", "brew", "pip", "python3", "node", "deno", "bun", "make"]
    static let questionStarters: Set<String> = ["what", "why", "how", "when", "where", "who", "which", "should", "can", "could",
                                                "would", "is", "are", "do", "does", "did", "will", "shall"]

    /// - Parameter sentenceCase: capitalize and punctuate as prose (false in Code mode: only hesitations and stutters go).
    public static func clean(_ text: String, sentenceCase: Bool = true) -> String {
        var words = text.split(whereSeparator: \.isWhitespace).map(String.init)

        // 1. Hesitation sounds (a trailing comma or period on the filler goes with it).
        words.removeAll { hesitations.contains(bare($0)) }

        // 2. Stutters: an immediately repeated 2–4 word sequence, or a doubled stutter-prone single word.
        var changed = true
        while changed {
            changed = false
            outer: for n in stride(from: 4, through: 1, by: -1) {
                var i = 0
                while i + 2 * n <= words.count {
                    let first = words[i..<i + n].map(bare), second = words[i + n..<i + 2 * n].map(bare)
                    let repeatable = n > 1 || stutterWords.contains(first[0])
                    // Only when the first copy has no sentence punctuation in between ("…done. Done…" is kept).
                    let interrupted = words[i..<i + n].contains { $0.last.map { ".!?".contains($0) } ?? false }
                    if repeatable, !first.contains(""), first == second, !interrupted {
                        words.removeSubrange(i..<i + n)
                        changed = true
                        break outer
                    }
                    i += 1
                }
            }
        }
        guard !words.isEmpty else { return "" }
        guard sentenceCase else { return words.joined(separator: " ") }

        // 3. Capitalize the first word when it's a plain lowercase word (not npm, getUserById, .env, …).
        let first = words[0]
        if let initial = first.first, initial.isLowercase, first.allSatisfy({ ($0.isLetter && $0.isLowercase) || $0 == "'" || $0 == "," }),
           !keepLowercase.contains(first) {
            words[0] = initial.uppercased() + first.dropFirst()
        }

        // 4. The pronoun "I" ("i", "i'm", "i'll", …) is always capitalized.
        for index in words.indices where words[index] == "i" || words[index].hasPrefix("i'") || words[index].hasPrefix("i’")
            || (words[index].count == 2 && words[index].hasPrefix("i") && ",.?!".contains(words[index].last!)) {
            words[index] = "I" + words[index].dropFirst()
        }

        // 5. End punctuation for sentences of 3+ words that lack it.
        var result = words.joined(separator: " ")
        if words.count >= 3, let last = result.last, last.isLetter || last.isNumber {
            // "Do not deploy…" / "Don't…" is an instruction, not a question.
            let negatedImperative = ["do", "does"].contains(bare(words[0])) && bare(words[1]) == "not"
            result += questionStarters.contains(bare(words[0])) && !negatedImperative ? "?" : "."
        }
        return result
    }

    /// Lowercased word without surrounding punctuation.
    static func bare(_ word: String) -> String {
        word.lowercased().trimmingCharacters(in: CharacterSet.punctuationCharacters)
    }
}
