import Foundation
import Testing
@testable import VoiceFlowCore

@Suite struct LanguageTests {
    @Test func outputLanguageResolution() {
        #expect(OutputLanguage.resolve(setting: .auto, detected: .de, hindiScript: .devanagari) == .german)
        #expect(OutputLanguage.resolve(setting: .auto, detected: .hi, hindiScript: .devanagari) == .hindiDevanagari)
        #expect(OutputLanguage.resolve(setting: .auto, detected: .hi, hindiScript: .hinglish) == .hinglish)
        #expect(OutputLanguage.resolve(setting: .auto, detected: nil, hindiScript: .hinglish) == .english)
        #expect(OutputLanguage.resolve(setting: .hinglish, detected: .en, hindiScript: .devanagari) == .hinglish)
        #expect(OutputLanguage.german.supportsOnDeviceRewrite && !OutputLanguage.hinglish.supportsOnDeviceRewrite)
    }

    @Test func routingKeepsTheEnglishModelForEnglish() {
        #expect(LanguageRouting.transcriptionModel(for: .en, multilingual: .largeV3Q5) == .mediumEnQ8)
        #expect(LanguageRouting.transcriptionModel(for: .hi, multilingual: .largeV3Q5) == .largeV3Q5)
        #expect(LanguageRouting.modelsToPrepare(setting: .auto, multilingual: .largeV3Q5).map(\.id) == ["large-v3-turbo-q8_0", "medium.en-q8_0"])
        #expect(LanguageRouting.modelsToPrepare(setting: .german, multilingual: .largeV3Q5).map(\.id) == ["large-v3-q5_0"])
        #expect(LanguageRouting.pick([.en: 0.2, .de: 0.7, .hi: 0.1]) == .de)
        #expect(DeveloperVocabulary.prompt(resource: "vocabulary-de")?.contains("Kubernetes") == true)
        #expect(DeveloperVocabulary.prompt(resource: LanguageRouting.promptResource(for: .hi, model: .largeV3Q5)) != nil)
        #expect(DeveloperVocabulary.prompt(resource: LanguageRouting.promptResource(for: .hi, model: .largeV3TurboQ8)) != nil)
    }

    @Test func languageCycleVisitsAll() {
        var seen: [DictationLanguage] = []
        var language = DictationLanguage.auto
        for _ in DictationLanguage.allCases { seen.append(language); language = language.next }
        #expect(Set(seen).count == DictationLanguage.allCases.count && language == .auto)
    }

    @Test func settingsDecodeLanguageTolerantly() throws {
        #expect(Settings.default.language == .auto && Settings.default.hindiScript == .devanagari)
        let s = try JSONDecoder().decode(Settings.self, from: Data(#"{"language": "german", "hindiScript": "hinglish", "multilingualModelID": "medium.en-q8_0"}"#.utf8))
        #expect(s.language == .german && s.hindiScript == .hinglish)
        #expect(s.multilingualModelID == STTModel.largeV3Q5.id) // English-only model can't be the multilingual one
        #expect(Settings.default.languageHotkey.displayName == "⌃⇧L")
    }

    @Test(arguments: [
        ("äh ich schicke dem Kunden morgen eine E-Mail", OutputLanguage.german, "Ich schicke dem Kunden morgen eine E-Mail."),
        ("kannst du bitte die Rechnung prüfen", OutputLanguage.german, "Kannst du bitte die Rechnung prüfen?"),
        ("यह bug production में सिर्फ़ तब आता है", OutputLanguage.hindiDevanagari, "यह bug production में सिर्फ़ तब आता है।"),
        ("क्या तुम check कर सकते हो", OutputLanguage.hindiDevanagari, "क्या तुम check कर सकते हो?"),
        ("kya tum check kar sakte ho", OutputLanguage.hinglish, "Kya tum check kar sakte ho?"),
        ("main main dont know", OutputLanguage.hinglish, "Main dont know."),
    ])
    func cleanupFollowsTheLanguage(input: String, language: OutputLanguage, expected: String) {
        #expect(RuleBasedCleanup.clean(input, language: language) == expected)
    }
}
