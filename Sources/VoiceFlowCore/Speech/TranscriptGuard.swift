import Foundation

/// Conservative post-STT cleanup of known Whisper failure modes. It only **removes** content the model is known
/// to invent (non-speech tags, repetition loops, stock phrases on near-silence). It never adds, replaces or
/// "corrects" words (spec rules 8–9).
///
/// Limitation: it can't detect a plausible inserted phrase (e.g. the "run dev" insertion seen once in the
/// benchmark). That's tracked by measurement (docs/ACCURACY.md, D3/D4), not guessed at here.
public enum TranscriptGuard {
    public enum Flag: String, Sendable, Hashable, CaseIterable {
        /// Removed bracketed/parenthesized non-speech tags such as "[BLANK_AUDIO]" or "(music)".
        case removedNonSpeechTag
        /// Collapsed an n-gram repeated 3+ times in a row (a decoder loop).
        case collapsedRepetition
        /// Dropped a stock phrase Whisper produces for silence/noise, given little detected speech.
        case droppedSilenceHallucination
    }

    static let nonSpeechTags: Set<String> = [
        "blank_audio", "blank audio", "silence", "music", "noise", "inaudible", "applause", "laughter", "no speech",
        "sound", "background noise",
    ]

    static let silenceHallucinations: Set<String> = [
        "thank you", "thanks for watching", "thank you for watching", "you", "bye", "thank you very much",
        "please subscribe", "subtitles by the amara.org community",
    ]

    /// - Parameter speechSeconds: speech detected in the recording (`RecordingAnalysis.speechSeconds`).
    public static func clean(_ text: String, speechSeconds: Double) -> (text: String, flags: Set<TranscriptGuard.Flag>) {
        var flags: Set<Flag> = []
        var result = removeNonSpeechTags(text, flags: &flags)
        result = collapseRepetitions(result, flags: &flags)
        result = result.split(whereSeparator: \.isWhitespace).joined(separator: " ")

        let normalized = result.lowercased().filter { $0.isLetter || $0 == " " || $0 == "." }
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        if speechSeconds < 1.0, silenceHallucinations.contains(normalized) {
            flags.insert(.droppedSilenceHallucination)
            result = ""
        }
        return (result, flags)
    }

    static let nonSpeechLastWords: Set<String> = ["music", "noise", "applause", "laughter", "laughs", "laughing",
                                                  "sighs", "silence", "coughs", "breathing"]

    /// A bracketed span is removed only if it's clearly a non-speech annotation, never ordinary words such as
    /// "array[index]".
    static func isNonSpeechTag(_ inner: Substring, opener: Character) -> Bool {
        let normalized = inner.lowercased().replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces)
        if nonSpeechTags.contains(normalized) { return true }
        if let last = normalized.split(separator: " ").last, nonSpeechLastWords.contains(String(last)) { return true }
        // Whisper's all-caps special tags, e.g. [BLANK_AUDIO], [MUSIC].
        let letters = inner.filter(\.isLetter)
        return opener == "[" && letters.count >= 3 && letters.allSatisfy(\.isUppercase)
            && inner.allSatisfy { $0.isLetter || $0 == "_" || $0 == " " }
    }

    static func removeNonSpeechTags(_ text: String, flags: inout Set<Flag>) -> String {
        var output = ""
        var index = text.startIndex
        while index < text.endIndex {
            let ch = text[index]
            if ch == "[" || ch == "(" || ch == "*" {
                let close: Character = ch == "[" ? "]" : ch == "(" ? ")" : "*"
                let afterOpen = text.index(after: index)
                if let end = text[afterOpen...].firstIndex(of: close), isNonSpeechTag(text[afterOpen..<end], opener: ch) {
                    flags.insert(.removedNonSpeechTag)
                    index = text.index(after: end)
                    continue
                }
            }
            output.append(ch)
            index = text.index(after: index)
        }
        return output
    }

    /// Collapses a decoder loop to one occurrence: a phrase of 2–8 words repeated 3+ times in a row, or a single word
    /// repeated 5+ times (so natural emphasis like "no, no, no" is left alone).
    static func collapseRepetitions(_ text: String, flags: inout Set<Flag>) -> String {
        var words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        func key(_ w: String) -> String { w.lowercased().filter { $0.isLetter || $0.isNumber } }
        var changed = true
        while changed {
            changed = false
            outer: for n in 1...max(1, min(8, words.count / 3)) {
                var i = 0
                while i + 3 * n <= words.count {
                    let gram = words[i..<i + n].map(key)
                    guard !gram.allSatisfy(\.isEmpty) else { i += 1; continue }
                    var repeats = 1
                    while i + (repeats + 1) * n <= words.count,
                          words[(i + repeats * n)..<(i + (repeats + 1) * n)].map(key) == gram {
                        repeats += 1
                    }
                    if repeats >= (n == 1 ? 5 : 3) {
                        words.removeSubrange((i + n)..<(i + repeats * n))
                        flags.insert(.collapsedRepetition)
                        changed = true
                        break outer
                    }
                    i += 1
                }
            }
        }
        return words.joined(separator: " ")
    }
}
