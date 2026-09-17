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
    /// Contractions written without an apostrophe, only where the bare form isn't also an English word
    /// ("cant", "wont", "its", "lets", "ill", "were", "id", "hell", "shell", "well" are left alone).
    static let contractions: [String: String] = [
        "dont": "don't", "doesnt": "doesn't", "didnt": "didn't", "isnt": "isn't", "arent": "aren't", "wasnt": "wasn't",
        "werent": "weren't", "havent": "haven't", "hasnt": "hasn't", "hadnt": "hadn't", "couldnt": "couldn't",
        "shouldnt": "shouldn't", "wouldnt": "wouldn't", "mustnt": "mustn't", "neednt": "needn't", "im": "I'm", "ive": "I've",
        "youre": "you're", "youve": "you've", "youll": "you'll", "theyre": "they're", "theyve": "they've", "theyll": "they'll",
        "weve": "we've", "thats": "that's", "whats": "what's", "theres": "there's", "shes": "she's", "hes": "he's",
        "wouldve": "would've", "couldve": "could've", "shouldve": "should've", "aint": "ain't", "heres": "here's",
        "wheres": "where's", "whos": "who's", "hows": "how's", "itll": "it'll", "thatll": "that'll",
    ]
    static let questionStarters: Set<String> = ["what", "why", "how", "when", "where", "who", "which", "should", "can", "could",
                                                "would", "is", "are", "do", "does", "did", "will", "shall"]

    /// Hesitation sounds in German and Hindi (Phase 14).
    static let otherHesitations: Set<String> = ["äh", "ähm", "öhm", "hm", "hmm", "उम्म", "अं", "हम्म", "आं"]
    static let germanStutterWords: Set<String> = ["der", "die", "das", "ein", "eine", "und", "ich", "wir", "es", "ist", "zu", "in", "den", "dem", "mit"]
    static let hindiStutterWords: Set<String> = ["मैं", "हम", "यह", "वह", "तो", "और", "कि", "के", "की", "का", "में", "main", "hum", "yeh", "to", "aur", "ki", "ke", "ka", "mein"]
    static let germanQuestionStarters: Set<String> = ["was", "warum", "wieso", "weshalb", "wie", "wann", "wo", "wohin", "woher", "wer", "wen",
                                                      "wem", "welche", "welcher", "welches", "kannst", "können", "könnte", "könnten", "ist",
                                                      "sind", "hast", "haben", "hat", "soll", "sollen", "sollte", "gibt", "darf", "dürfen",
                                                      "würdest", "würden", "willst", "wollen", "musst", "müssen", "bist", "seid", "machst"]
    static let hindiQuestionStarters: Set<String> = ["क्या", "कैसे", "क्यों", "कब", "कहाँ", "कहां", "कौन", "किस", "कितना", "कितने", "कितनी",
                                                     "kya", "kaise", "kyun", "kyon", "kab", "kahan", "kaun", "kis", "kitna", "kitne", "kitni"]

    /// - Parameter sentenceCase: capitalize and punctuate as prose (false in Code mode: only hesitations and stutters go).
    /// - Parameter language: the output language; hesitations, stutter words, question words and end punctuation follow it.
    public static func clean(_ text: String, sentenceCase: Bool = true, language: OutputLanguage = .english) -> String {
        var words = text.split(whereSeparator: \.isWhitespace).map(String.init)

        // 1. Hesitation sounds (a trailing comma or period on the filler goes with it).
        words.removeAll { hesitations.contains(bare($0)) || (language != .english && otherHesitations.contains(bare($0))) }

        // 2. Stutters: an immediately repeated 2–4 word sequence, or a doubled stutter-prone single word.
        var changed = true
        while changed {
            changed = false
            outer: for n in stride(from: 4, through: 1, by: -1) {
                var i = 0
                while i + 2 * n <= words.count {
                    let first = words[i..<i + n].map(bare), second = words[i + n..<i + 2 * n].map(bare)
                    let singles = switch language {
                    case .english: stutterWords
                    case .german: germanStutterWords
                    case .hindiDevanagari, .hinglish: hindiStutterWords
                    }
                    let repeatable = n > 1 || singles.contains(first[0])
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

        // Missing apostrophes in unambiguous contractions ("dont" → "don't"); keeps a capital first letter. English only.
        for index in words.indices where language == .english {
            let token = words[index]
            let coreEnd = token.lastIndex { $0.isLetter }.map(token.index(after:)) ?? token.startIndex
            let core = String(token[..<coreEnd])
            guard core.allSatisfy(\.isLetter), let fixed = contractions[core.lowercased()] else { continue }
            let cased = core.first!.isUppercase && fixed.first!.isLowercase ? fixed.prefix(1).uppercased() + fixed.dropFirst() : fixed
            words[index] = cased + token[coreEnd...]
        }

        // 3. Capitalize the first word when it's a plain lowercase word (not npm, getUserById, .env, …).
        let first = words[0]
        if let initial = first.first, initial.isLowercase, first.allSatisfy({ ($0.isLetter && $0.isLowercase) || $0 == "'" || $0 == "," }),
           !keepLowercase.contains(first) {
            words[0] = initial.uppercased() + first.dropFirst()
        }

        // 4. The pronoun "I" ("i", "i'm", "i'll", …) is always capitalized.
        for index in words.indices where language == .english && (words[index] == "i" || words[index].hasPrefix("i'") || words[index].hasPrefix("i’"))
            || (words[index].count == 2 && words[index].hasPrefix("i") && ",.?!".contains(words[index].last!)) {
            words[index] = "I" + words[index].dropFirst()
        }

        // 5. End punctuation for sentences of 3+ words that lack it.
        var result = words.joined(separator: " ")
        if words.count >= 3, let last = result.last, last.isLetter || last.isNumber {
            // "Do not deploy…" / "Don't…" is an instruction, not a question.
            let negatedImperative = ["do", "does"].contains(bare(words[0])) && bare(words[1]) == "not"
            let starters = switch language {
            case .english: questionStarters
            case .german: germanQuestionStarters
            case .hindiDevanagari, .hinglish: hindiQuestionStarters
            }
            let isQuestion = starters.contains(bare(words[0])) && !negatedImperative
            // Hindi in Devanagari ends statements with the danda "।".
            result += isQuestion ? "?" : (language == .hindiDevanagari ? "।" : ".")
        }
        return result
    }

    /// Lowercased word without surrounding punctuation.
    static func bare(_ word: String) -> String {
        word.lowercased().trimmingCharacters(in: CharacterSet.punctuationCharacters)
    }
}
