import Foundation

/// The language setting (Phase 14). Auto detects English, German or Hindi on each dictation; the others fix it.
public enum DictationLanguage: String, Codable, CaseIterable, Sendable {
    case auto, english, german, hindi, hinglish

    public var displayName: String {
        switch self {
        case .auto: "Auto-detect"
        case .english: "English"
        case .german: "German (Deutsch)"
        case .hindi: "Hindi (देवनागरी)"
        case .hinglish: "Hinglish (Hindi in Latin letters)"
        }
    }

    /// Short label for the pill and menu bar.
    public var badge: String {
        switch self {
        case .auto: "Auto"
        case .english: "EN"
        case .german: "DE"
        case .hindi: "हि"
        case .hinglish: "Hing"
        }
    }

    /// Order for the switch-language shortcut.
    public var next: DictationLanguage {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

/// A language Whisper can detect and transcribe.
public enum SpokenLanguage: String, Codable, CaseIterable, Sendable {
    case en, de, hi
}

/// How Hindi is written when Auto detects it.
public enum HindiScript: String, Codable, CaseIterable, Sendable {
    case devanagari, hinglish
}

/// What a dictation is written as: the spoken language plus, for Hindi, the script.
public enum OutputLanguage: String, Sendable, CaseIterable {
    case english, german, hindiDevanagari, hinglish

    public static func resolve(setting: DictationLanguage, detected: SpokenLanguage?, hindiScript: HindiScript) -> OutputLanguage {
        switch setting {
        case .english: return .english
        case .german: return .german
        case .hindi: return .hindiDevanagari
        case .hinglish: return .hinglish
        case .auto:
            switch detected ?? .en {
            case .en: return .english
            case .de: return .german
            case .hi: return hindiScript == .hinglish ? .hinglish : .hindiDevanagari
            }
        }
    }

    public var spoken: SpokenLanguage {
        switch self {
        case .english: .en
        case .german: .de
        case .hindiDevanagari, .hinglish: .hi
        }
    }

    public var badge: String {
        switch self {
        case .english: "EN"
        case .german: "DE"
        case .hindiDevanagari: "हि"
        case .hinglish: "Hing"
        }
    }

    /// Apple's on-device model supports English and German, not Hindi (checked on this Mac, 2026-09-17). Other languages
    /// get the rule-based modes; Prompt and Writing fall back to Clean.
    public var supportsOnDeviceRewrite: Bool { self == .english || self == .german }

    /// Written in Latin letters (capitalization and Latin punctuation rules apply).
    public var usesLatinScript: Bool { self != .hindiDevanagari }
}

/// Model choice and text conversion per language.
public enum LanguageRouting {
    /// Detects English/German/Hindi: widest margins on the owner's English recordings (docs/ACCURACY.md §9).
    public static let detectorModel = STTModel.largeV3TurboQ8

    /// English keeps the model that passed the English gate; German and Hindi use the multilingual model.
    public static func transcriptionModel(for spoken: SpokenLanguage, multilingual: STTModel) -> STTModel {
        spoken == .en ? .mediumEnQ8 : multilingual
    }

    /// Models to load when recording starts.
    public static func modelsToPrepare(setting: DictationLanguage, multilingual: STTModel) -> [STTModel] {
        var models: [STTModel]
        switch setting {
        case .english: models = [.mediumEnQ8]
        case .german, .hindi, .hinglish: models = [multilingual]
        case .auto: models = [detectorModel, .mediumEnQ8]
        }
        var seen = Set<String>()
        return models.filter { seen.insert($0.id).inserted }
    }

    /// Bundled vocabulary prompt resource (Resources/<name>.txt) for a language and model.
    public static func promptResource(for spoken: SpokenLanguage, model: STTModel) -> String {
        switch spoken {
        case .en: "developer-vocabulary"
        case .de: "vocabulary-de"
        // large-v3 did best with a romanized prompt, turbo with a Devanagari one (still writing Devanagari): §9.
        case .hi: model.id.hasPrefix("large-v3-turbo") ? "vocabulary-hi-devanagari" : "vocabulary-hi-romanized"
        }
    }

    /// Converts the recognizer's text for the output: Devanagari keeps Hindi words and restores Latin English words;
    /// Hinglish romanizes.
    public static func convert(_ text: String, to output: OutputLanguage) -> String {
        switch output {
        case .english, .german: text
        case .hindiDevanagari: HindiTransliteration.devanagariPunctuation(HindiTransliteration.latinizeLoanwords(text))
        case .hinglish: HindiTransliteration.hinglish(text)
        }
    }

    /// Most likely language among the supported ones.
    public static func pick(_ probabilities: [SpokenLanguage: Double]) -> SpokenLanguage {
        probabilities.max { $0.value < $1.value }?.key ?? .en
    }
}
