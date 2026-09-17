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

    /// Lowercased word tokens: punctuation removed (apostrophes dropped, other symbols split),
    /// number words 0–99 converted to digits so "fifteen" == "15".
    public static func words(_ text: String) -> [String] {
        var cleaned = ""
        cleaned.reserveCapacity(text.count)
        for ch in text.lowercased() {
            if ch.isLetter || ch.isNumber { cleaned.append(ch) }
            else if ch == "'" || ch == "’" { continue }
            else { cleaned.append(" ") }
        }
        let raw = cleaned.split(separator: " ").map(String.init)
        return numbersToDigits(raw)
    }

    static func numbersToDigits(_ tokens: [String]) -> [String] {
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
