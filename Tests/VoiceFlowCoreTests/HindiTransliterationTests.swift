import Testing
@testable import VoiceFlowCore

@Suite struct HindiTransliterationTests {
    @Test(arguments: [
        ("कल की meeting को postpone कर देते हैं, मुझे थोड़ा और time चाहिए।", "Kal ki meeting ko postpone kar dete hain, mujhe thoda aur time chahiye."),
        ("इस function में getUserById call करो और result को Redis में cache कर दो।", "Is function mein getUserById call karo aur result ko Redis mein cache kar do."),
        ("Kubernetes पर pods बार-बार crash हो रहे हैं।", "Kubernetes par pods baar-baar crash ho rahe hain."),
        ("मैंने checkout page वाला bug देखा। अब फ़ाइल चेक करो।", "Maine checkout page wala bug dekha. Ab file check karo."),
    ])
    func devanagariToHinglish(input: String, expected: String) {
        #expect(HindiTransliteration.hinglish(input) == expected)
    }

    @Test(arguments: [
        ("करते", "karte"), ("पिछले", "pichhle"), ("अगले", "agle"), ("लेगा", "lega"), ("होगी", "hogi"), ("कमल", "kamal"),
        ("समझना", "samajhna"), ("ज़रूरी", "zaroori"), ("फ़ोन", "fon"),
    ])
    func letterRules(word: String, expected: String) {
        #expect(HindiTransliteration.romanize(word) == expected)
    }

    @Test func loanwordsBecomeLatinButHindiStays() {
        #expect(HindiTransliteration.latinizeLoanwords("यह फ़ाइल चेक करो और डॉकर रीस्टार्ट करो।") == "यह file check करो और Docker restart करो।")
        #expect(HindiTransliteration.hinglish("already Latin text.") == "Already Latin text.")
    }
}
