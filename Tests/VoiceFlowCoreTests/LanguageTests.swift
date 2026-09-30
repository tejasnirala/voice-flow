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

    @Test func routingUsesTheRightModelPerLanguage() {
        let models = Settings.default.languageModels
        #expect(LanguageRouting.transcriptionModel(for: .en, models: models) == .mediumEnQ8)
        #expect(LanguageRouting.transcriptionModel(for: .de, models: models) == .largeV3Q5)
        // Hindi uses the detector model, so Auto loads one model fewer.
        #expect(LanguageRouting.transcriptionModel(for: .hi, models: models) == LanguageRouting.detectorModel)
        #expect(LanguageRouting.modelsToPrepare(setting: .auto, models: models).map(\.id) == ["large-v3-turbo-q8_0", "medium.en-q8_0"])
        #expect(LanguageRouting.modelsToPrepare(setting: .hinglish, models: models) == [.largeV3TurboQ8])
        #expect(LanguageRouting.modelsToPrepare(setting: .german, models: models) == [.largeV3Q5])
        #expect(LanguageRouting.pick([.en: 0.2, .de: 0.7, .hi: 0.1]) == .de)
        #expect(DeveloperVocabulary.prompt(resource: "vocabulary-de")?.contains("Kubernetes") == true)
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
        let s = try JSONDecoder().decode(Settings.self, from: Data(#"{"language": "german", "hindiScript": "hinglish", "germanModelID": "medium.en-q8_0", "hindiModelID": "medium-q8_0"}"#.utf8))
        #expect(s.language == .german && s.hindiScript == .hinglish)
        #expect(s.germanModelID == STTModel.largeV3Q5.id)      // English-only model can't transcribe German
        #expect(s.hindiModelID == STTModel.mediumQ8.id)        // a multilingual model is accepted
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

    @Test func urduCountsAsHindiAndLowMassIsUncertain() {
        // Owner's short WhatsApp Hindi looked like this before: only English scored among the three.
        let d = LanguageRouting.interpret(["en": 0.06, "de": 0.0, "hi": 0.02, "ur": 0.61])
        #expect(d.language == .hi && d.confident)
        let noise = LanguageRouting.interpret(["en": 0.13, "de": 0.0, "hi": 0.0, "ur": 0.02])
        #expect(!noise.confident)
        #expect(LanguageRouting.interpret(["en": 0.97, "de": 0.01, "hi": 0.0, "ur": 0.0]) == .init(language: .en, probabilities: [.en: 0.97, .de: 0.01, .hi: 0.0], confident: true))
    }

    @Test func perAppLanguage() throws {
        var s = Settings.default
        s.appLanguages = ["net.whatsapp.WhatsApp": .hinglish]
        #expect(s.language(forApp: "net.whatsapp.WhatsApp") == .hinglish)
        #expect(s.language(forApp: "com.microsoft.VSCode") == .auto)
        #expect(s.language(forApp: nil) == .auto)
        let decoded = try JSONDecoder().decode(Settings.self, from: Data(#"{"appLanguages": {"a": "hindi", "b": "klingon"}}"#.utf8))
        #expect(decoded.appLanguages == ["a": .hindi])
    }

    @Test func germanModelIsOptionalUnlessGermanIsChosen() {
        let models = Settings.default.languageModels
        // Auto or English/Hindi never requires the German model.
        #expect(!LanguageRouting.requiredModels(setting: .auto, appLanguages: [:], models: models).contains(.largeV3Q5))
        #expect(LanguageRouting.requiredModels(setting: .auto, appLanguages: [:], models: models).map(\.id)
                == ["large-v3-turbo-q8_0", "medium.en-q8_0"])
        #expect(LanguageRouting.requiredModels(setting: .hinglish, appLanguages: [:], models: models) == [.largeV3TurboQ8])
        // Choosing German, globally or for one app, requires it.
        #expect(LanguageRouting.requiredModels(setting: .german, appLanguages: [:], models: models) == [.largeV3Q5])
        #expect(LanguageRouting.requiredModels(setting: .auto, appLanguages: ["x": .german], models: models).contains(.largeV3Q5))
        // Detected German without its model falls back to the multilingual detector.
        #expect(LanguageRouting.fallbackModel(for: .de) == LanguageRouting.detectorModel)
        #expect(LanguageRouting.fallbackModel(for: .en) == nil && LanguageRouting.fallbackModel(for: .hi) == nil)
    }
}
