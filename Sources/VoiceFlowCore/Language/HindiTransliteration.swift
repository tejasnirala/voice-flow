import Foundation

/// Devanagari → casual romanized Hindi ("Hinglish"), and English loanwords written in Devanagari → English (Phase 14).
/// Whisper transcribes Hindi speech reliably only in Devanagari; Hinglish is produced from that text by rules:
/// a lexicon of common words in their usual Hinglish spelling, then letter-by-letter romanization with schwa deletion.
/// Latin words (English terms the recognizer already wrote in Latin) pass through unchanged.
public enum HindiTransliteration {
    // MARK: English loanwords

    /// English words Whisper sometimes writes in Devanagari. Mapped back to Latin in both Hindi output styles
    /// (owner decision: English words stay in Latin). Only unambiguous loanwords.
    static let loanwords: [String: String] = [
        "चेक": "check", "फ़ाइल": "file", "फाइल": "file", "कॉल": "call", "कोड": "code", "सर्वर": "server", "बग": "bug",
        "मीटिंग": "meeting", "टाइम": "time", "अपडेट": "update", "डिज़ाइन": "design", "डिजाइन": "design", "क्लाइंट": "client",
        "प्रोजेक्ट": "project", "डेटाबेस": "database", "डाटाबेस": "database", "फंक्शन": "function", "फ़ंक्शन": "function",
        "रिज़ल्ट": "result", "रिजल्ट": "result", "कैश": "cache", "डिप्लॉय": "deploy", "डिप्लॉयमेंट": "deployment",
        "प्रोडक्शन": "production", "यूज़र": "user", "यूजर": "user", "लॉगिन": "login", "लॉग": "log", "टेस्ट": "test",
        "कमिट": "commit", "पुश": "push", "पुल": "pull", "रिक्वेस्ट": "request", "रिस्पॉन्स": "response", "रिस्पांस": "response",
        "एपीआई": "API", "टोकन": "token", "सर्विस": "service", "पेज": "page", "ऐप": "app", "एप": "app", "मोबाइल": "mobile",
        "लैपटॉप": "laptop", "ईमेल": "email", "मैसेज": "message", "डॉक्यूमेंट": "document", "इनवॉइस": "invoice",
        "रीस्टार्ट": "restart", "स्टार्ट": "start", "स्टॉप": "stop", "सेटिंग": "setting", "सेटिंग्स": "settings",
        "ब्रांच": "branch", "मर्ज": "merge", "रिव्यू": "review", "फ़्रंटएंड": "frontend", "फ्रंटएंड": "frontend",
        "बैकएंड": "backend", "कंटेनर": "container", "इमेज": "image", "टाइमआउट": "timeout", "एंडपॉइंट": "endpoint",
        "क्रैश": "crash", "हेल्थ": "health", "वर्ज़न": "version", "वर्जन": "version", "रोलबैक": "rollback", "रजिस्ट्री": "registry",
        "पॉड्स": "pods", "पॉड": "pod", "हुक": "hook", "ऐरे": "array", "प्लान": "plan", "सेशन": "session", "लोकली": "locally",
        "फ्लो": "flow", "इश्यूज़": "issues", "इश्यू": "issue", "लेआउट": "layout", "प्राइसिंग": "pricing", "क्विक": "quick",
        "पोस्टपोन": "postpone", "डॉकर": "Docker", "रेडिस": "Redis", "गिट": "git", "गिटहब": "GitHub", "नेक्स्ट": "Next",
        "टाइपस्क्रिप्ट": "TypeScript", "जावास्क्रिप्ट": "JavaScript", "रिएक्ट": "React", "कुबेरनेट्स": "Kubernetes",
    ]

    /// Replaces Devanagari-written loanwords with English (for the Devanagari output style).
    public static func latinizeLoanwords(_ text: String) -> String {
        mapWords(text) { core in loanwords[core] }
    }

    /// A sentence-ending "." right after a Devanagari word becomes the danda "।" ("Next.js" and English sentences keep ".").
    public static func devanagariPunctuation(_ text: String) -> String {
        var result = ""
        let chars = Array(text)
        for (i, ch) in chars.enumerated() {
            let atSentenceEnd = i + 1 == chars.count || chars[i + 1] == " " || chars[i + 1] == "\n"
            let afterDevanagari = i > 0 && chars[i - 1].unicodeScalars.contains { (0x0900...0x097F).contains($0.value) }
            result.append(ch == "." && atSentenceEnd && afterDevanagari ? "।" : ch)
        }
        return result
    }

    // MARK: Hinglish

    /// Common words in their usual Hinglish spelling (the letter rules can't know conventions like "hain", "mein").
    static let lexicon: [String: String] = [
        "है": "hai", "हैं": "hain", "में": "mein", "मैं": "main", "नहीं": "nahi", "ना": "na", "क्या": "kya", "की": "ki",
        "का": "ka", "के": "ke", "को": "ko", "से": "se", "पर": "par", "और": "aur", "या": "ya", "यह": "yeh", "ये": "ye",
        "वह": "woh", "वो": "woh", "मुझे": "mujhe", "मेरा": "mera", "मेरी": "meri", "मेरे": "mere", "हम": "hum", "हमें": "hamein",
        "हमारा": "hamara", "तुम": "tum", "तुम्हें": "tumhe", "आप": "aap", "आपको": "aapko", "कि": "ki", "तो": "to", "भी": "bhi",
        "ही": "hi", "था": "tha", "थी": "thi", "थे": "the", "हो": "ho", "हुआ": "hua", "हुई": "hui", "गया": "gaya", "गई": "gayi",
        "रहा": "raha", "रही": "rahi", "रहे": "rahe", "कर": "kar", "करो": "karo", "करना": "karna", "करके": "karke",
        "करेंगे": "karenge", "करूँगा": "karunga", "करूंगा": "karunga", "दो": "do", "दे": "de", "देते": "dete", "लो": "lo",
        "लेना": "lena", "चाहिए": "chahiye", "सकते": "sakte", "सकता": "sakta", "सके": "sake", "थोड़ा": "thoda", "थोड़ी": "thodi",
        "बहुत": "bahut", "अभी": "abhi", "कल": "kal", "आज": "aaj", "फिर": "phir", "पहले": "pehle", "बाद": "baad", "लिए": "liye",
        "इसलिए": "isliye", "क्योंकि": "kyunki", "अगर": "agar", "जब": "jab", "तब": "tab", "सिर्फ़": "sirf", "सिर्फ": "sirf",
        "सब": "sab", "कुछ": "kuch", "एक": "ek", "दो बार": "do baar", "बार": "baar", "वाला": "wala", "वाली": "wali",
        "धन्यवाद": "dhanyavaad", "कृपया": "kripya", "ठीक": "theek", "अच्छा": "achha", "हाँ": "haan", "हां": "haan",
        "यहाँ": "yahan", "वहाँ": "wahan", "कैसे": "kaise", "क्यों": "kyun", "कब": "kab", "कहाँ": "kahan", "कौन": "kaun",
        "इस": "is", "उस": "us", "इसे": "ise", "उसे": "use", "अपना": "apna", "अलग": "alag", "नया": "naya", "नए": "naye",
        "नई": "nayi", "खुश": "khush", "काफ़ी": "kaafi", "काफी": "kaafi", "उम्मीद": "ummeed", "बाकी": "baaki", "सारा": "saara",
        "मुझी": "mujhe", "हफ़्ते": "hafte", "हफ्ते": "hafte", "शाम": "shaam", "घर": "ghar", "काम": "kaam", "बात": "baat",
        "लगता": "lagta", "देखा": "dekha", "देख": "dekh", "चलाने": "chalane", "चला": "chala", "रखो": "rakho", "मत": "mat",
        "मैंने": "maine", "हमने": "humne", "तुमने": "tumne", "उसने": "usne", "करते": "karte", "करने": "karne",
        "रखते": "rakhte", "बारिश": "baarish", "बाहर": "bahar", "पहुँचूँगा": "pahunchunga", "देर": "der", "छुट्टी": "chhutti", "लेनी": "leni",
    ]

    static let consonants: [UInt32: String] = [
        0x0915: "k", 0x0916: "kh", 0x0917: "g", 0x0918: "gh", 0x0919: "n", 0x091A: "ch", 0x091B: "chh", 0x091C: "j",
        0x091D: "jh", 0x091E: "n", 0x091F: "t", 0x0920: "th", 0x0921: "d", 0x0922: "dh", 0x0923: "n", 0x0924: "t",
        0x0925: "th", 0x0926: "d", 0x0927: "dh", 0x0928: "n", 0x092A: "p", 0x092B: "ph", 0x092C: "b", 0x092D: "bh",
        0x092E: "m", 0x092F: "y", 0x0930: "r", 0x0932: "l", 0x0935: "v", 0x0936: "sh", 0x0937: "sh", 0x0938: "s",
        0x0939: "h", 0x0933: "l",
        // Precomposed nukta letters.
        0x0958: "q", 0x0959: "kh", 0x095A: "gh", 0x095B: "z", 0x095C: "d", 0x095D: "dh", 0x095E: "f", 0x095F: "y",
    ]
    /// Consonant + nukta (U+093C) spelled as two code points.
    static let nuktaForms: [UInt32: String] = [0x0915: "q", 0x0916: "kh", 0x0917: "gh", 0x091C: "z", 0x0921: "d", 0x0922: "dh", 0x092B: "f"]
    static let independentVowels: [UInt32: String] = [
        0x0905: "a", 0x0906: "aa", 0x0907: "i", 0x0908: "ee", 0x0909: "u", 0x090A: "oo", 0x090B: "ri", 0x090F: "e",
        0x0910: "ai", 0x0913: "o", 0x0914: "au",
    ]
    static let vowelSigns: [UInt32: String] = [
        0x093E: "aa", 0x093F: "i", 0x0940: "ee", 0x0941: "u", 0x0942: "oo", 0x0943: "ri", 0x0947: "e", 0x0948: "ai",
        0x094B: "o", 0x094C: "au",
    ]
    static let virama: UInt32 = 0x094D, nukta: UInt32 = 0x093C, anusvara: UInt32 = 0x0902, chandrabindu: UInt32 = 0x0901, visarga: UInt32 = 0x0903

    /// Devanagari text → Hinglish. Punctuation "।" becomes "."; Latin words are kept; the first letter of a sentence is
    /// capitalized.
    public static func hinglish(_ text: String) -> String {
        let latinLoanwords = latinizeLoanwords(text).replacingOccurrences(of: "।", with: ".").replacingOccurrences(of: "॥", with: ".")
        let romanized = mapWords(latinLoanwords) { core in
            guard core.unicodeScalars.contains(where: { (0x0900...0x097F).contains($0.value) }) else { return nil }
            return lexicon[core] ?? romanize(core)
        }
        return capitalizeSentences(romanized)
    }

    /// Code-point romanization of one Devanagari word with schwa deletion.
    static func romanize(_ word: String) -> String {
        let scalars = word.unicodeScalars.map(\.value)
        var units: [(consonant: String?, vowel: String?, explicitVowel: Bool)] = []
        var i = 0
        while i < scalars.count {
            let value = scalars[i]
            if var consonant = consonants[value] {
                var next = i + 1
                if next < scalars.count, scalars[next] == nukta {
                    consonant = nuktaForms[value] ?? consonant
                    next += 1
                }
                if next < scalars.count, let sign = vowelSigns[scalars[next]] {
                    units.append((consonant, sign, true)); i = next + 1
                } else if next < scalars.count, scalars[next] == virama {
                    units.append((consonant, nil, true)); i = next + 1
                } else {
                    units.append((consonant, "a", false)); i = next
                }
            } else if let vowel = independentVowels[value] {
                units.append((nil, vowel, true)); i += 1
            } else if value == anusvara || value == chandrabindu {
                units.append((nil, "n", true)); i += 1
            } else if value == visarga {
                units.append((nil, "h", true)); i += 1
            } else if value == nukta || value == virama {
                i += 1
            } else {
                units.append((String(UnicodeScalar(value).map(Character.init) ?? " "), nil, true)); i += 1
            }
        }
        // Schwa deletion: drop the inherent "a" at the end of a word, and between a vowel and a consonant that has its
        // own vowel ("samajhna", "badhakar").
        var out = ""
        for (index, unit) in units.enumerated() {
            var vowel = unit.vowel
            if !unit.explicitVowel, unit.consonant != nil {
                let isLast = index == units.count - 1
                // "karte", "pichhle", "agle": the next consonant carries a written vowel sign; "kamal" keeps its middle "a".
                let nextHasVowelSign = index + 1 < units.count && units[index + 1].consonant != nil
                    && units[index + 1].explicitVowel && units[index + 1].vowel != nil
                let previousHasVowel = index > 0 && units[index - 1].vowel != nil
                if (isLast && units.count > 1) || (index >= 1 && previousHasVowel && nextHasVowelSign) {
                    vowel = nil
                }
            }
            out += (unit.consonant ?? "") + (vowel ?? "")
        }
        // Casual spelling writes word-final long vowels short: "lega", "hogi", "badha".
        for (long, short) in [("aa", "a"), ("ee", "i"), ("oo", "u")] where out.count > 3 && out.hasSuffix(long) {
            out = String(out.dropLast(long.count)) + short
        }
        return out
    }

    // MARK: Helpers

    /// Applies `transform` to the core of each whitespace token (punctuation kept); nil keeps the token.
    static func mapWords(_ text: String, _ transform: (String) -> String?) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            line.split(separator: " ", omittingEmptySubsequences: false).map { token -> String in
                let t = String(token)
                let edge = CharacterSet(charactersIn: ".,;:!?\"'()[]।॥-")
                guard let start = t.unicodeScalars.firstIndex(where: { !edge.contains($0) }) else { return t }
                let end = t.unicodeScalars.lastIndex(where: { !edge.contains($0) })!
                let lead = String(t.unicodeScalars[..<start]), core = String(t.unicodeScalars[start...end])
                let trail = String(t.unicodeScalars[t.unicodeScalars.index(after: end)...])
                // Hyphenated words ("बार-बार") map part by part.
                if core.contains("-") {
                    let parts = core.split(separator: "-").map { transform(String($0)) ?? String($0) }
                    return lead + parts.joined(separator: "-") + trail
                }
                return lead + (transform(core) ?? core) + trail
            }.joined(separator: " ")
        }.joined(separator: "\n")
    }

    static func capitalizeSentences(_ text: String) -> String {
        var result = ""
        var capitalizeNext = true
        for ch in text {
            if capitalizeNext, ch.isLetter {
                result += ch.isLowercase ? ch.uppercased() : String(ch)
                capitalizeNext = false
            } else {
                result.append(ch)
                if ".!?\n".contains(ch) { capitalizeNext = true }
            }
        }
        return result
    }
}
