import Foundation

/// Normalizes transcripts for spelling-agnostic accuracy scoring.
///
/// Scoring asks "did the engine hear the right words?", separately from "did it format them
/// well?". So `getUserById`, `get user by ID` and `Get user by id.` all normalize to the same
/// thing, while `get user by eid` does not.
public enum TranscriptNormalizer {
    /// Spoken separators that may appear between the parts of a term ("dot env", "user underscore id").
    static let separatorWords: Set<String> = ["dot", "dash", "hyphen", "underscore", "slash"]

    static let units = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
                        "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen"]
    static let tens = ["twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90]

    /// Equivalent spellings that aren't recognition errors: contractions (a speaker saying "I'll" and an
    /// engine writing "I will" heard the same words) and informal spellings. Matched before apostrophes are removed.
    static let equivalents: [String: [String]] = [
        "i'm": ["i", "am"], "i'll": ["i", "will"], "i've": ["i", "have"], "i'd": ["i", "would"],
        "you're": ["you", "are"], "you'll": ["you", "will"], "you've": ["you", "have"],
        "we're": ["we", "are"], "we'll": ["we", "will"], "we've": ["we", "have"],
        "they're": ["they", "are"], "they'll": ["they", "will"], "they've": ["they", "have"],
        "it's": ["it", "is"], "that's": ["that", "is"], "there's": ["there", "is"], "what's": ["what", "is"],
        "let's": ["let", "us"], "can't": ["can", "not"], "cannot": ["can", "not"], "won't": ["will", "not"],
        "don't": ["do", "not"], "doesn't": ["does", "not"], "didn't": ["did", "not"],
        "isn't": ["is", "not"], "aren't": ["are", "not"], "wasn't": ["was", "not"], "weren't": ["were", "not"],
        "haven't": ["have", "not"], "hasn't": ["has", "not"], "hadn't": ["had", "not"],
        "shouldn't": ["should", "not"], "wouldn't": ["would", "not"], "couldn't": ["could", "not"],
        "ok": ["okay"],
    ]

    /// Lowercased word tokens: punctuation removed (other symbols split), contractions expanded,
    /// number words 0–99 converted to digits so "fifteen" == "15".
    public static func words(_ text: String) -> [String] {
        var cleaned = ""
        cleaned.reserveCapacity(text.count)
        for ch in text.lowercased() {
            if ch.isLetter || ch.isNumber || ch == "'" { cleaned.append(ch) }
            else if ch == "’" { cleaned.append("'") }
            else { cleaned.append(" ") }
        }
        var tokens: [String] = []
        for raw in cleaned.split(separator: " ") {
            let token = raw.trimmingCharacters(in: CharacterSet(charactersIn: "'"))
            guard !token.isEmpty else { continue }
            if let expansion = equivalents[token] { tokens.append(contentsOf: expansion) }
            else { tokens.append(token.replacingOccurrences(of: "'", with: "")) }
        }
        return numbersToDigits(tokens)
    }

    static func numbersToDigits(_ tokens: [String]) -> [String] {
        var converted = numberWordsToDigits(tokens)
        // Spoken codes: "four oh four" → "404" (digit, "oh", digit).
        var i = 0
        while i + 2 < converted.count {
            if converted[i].count == 1, converted[i].first!.isNumber, converted[i + 1] == "oh",
               converted[i + 2].count == 1, converted[i + 2].first!.isNumber {
                converted.replaceSubrange(i...(i + 2), with: [converted[i] + "0" + converted[i + 2]])
            }
            i += 1
        }
        return converted
    }

    static func numberWordsToDigits(_ tokens: [String]) -> [String] {
        var out: [String] = []
        var i = 0
        while i < tokens.count {
            let t = tokens[i]
            if let ten = tens[t] {
                if i + 1 < tokens.count, let u = units.firstIndex(of: tokens[i + 1]), (1...9).contains(u) {
                    out.append(String(ten + u)); i += 2; continue
                }
                out.append(String(ten))
            } else if let u = units.firstIndex(of: t) {
                out.append(String(u))
            } else {
                out.append(t)
            }
            i += 1
        }
        return out
    }

    /// Separator-free key for a term: "Next.js" → "nextjs", "npm run dev" → "npmrundev".
    public static func key(_ term: String) -> String {
        words(term).joined()
    }

    /// Replaces every run of tokens whose concatenation equals a variant key with that variant's
    /// canonical key, ignoring spoken separator words inside the run. Longest variants win.
    /// `variants` maps variant key → canonical key (a canonical key maps to itself).
    public static func mergeTerms(_ tokens: [String], variants: [String: String]) -> [String] {
        let sortedKeys = variants.keys.filter { !$0.isEmpty }.sorted { $0.count > $1.count }
        guard !sortedKeys.isEmpty else { return tokens }
        var out: [String] = []
        var i = 0
        outer: while i < tokens.count {
            for key in sortedKeys {
                if let end = matchRun(tokens, from: i, key: key) {
                    out.append(variants[key]!); i = end; continue outer
                }
            }
            out.append(tokens[i]); i += 1
        }
        return out
    }

    public static func mergeTerms(_ tokens: [String], keys: [String]) -> [String] {
        mergeTerms(tokens, variants: Dictionary(keys.map { ($0, $0) }, uniquingKeysWith: { a, _ in a }))
    }

    /// If tokens[start...] concatenate (skipping separator words) to exactly `key`, returns the end index.
    static func matchRun(_ tokens: [String], from start: Int, key: String) -> Int? {
        var built = ""
        var j = start
        while j < tokens.count {
            let t = tokens[j]
            if separatorWords.contains(t) && !key.hasPrefix(built + t) {
                j += 1; continue
            }
            let candidate = built + t
            guard key.hasPrefix(candidate) else { return nil }
            built = candidate; j += 1
            if built == key { return j }
        }
        return nil
    }
}
