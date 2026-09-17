/// User settings persisted as JSON (`~/Library/Application Support/VoiceFlow/settings.json`).
///
/// Decoding is forward- and backward-tolerant: missing keys take their defaults and unknown keys are
/// ignored, so adding a setting never invalidates an existing file.
public struct Settings: Codable, Equatable, Sendable {
    public enum ProcessingMode: String, Codable, Sendable, CaseIterable {
        /// Audio → STT → paste. No LLM.
        case fast
        /// Audio → STT → local LLM → paste (Phase 7).
        case smart
    }

    /// How dictation is triggered.
    public enum DictationTrigger: String, Codable, Sendable, CaseIterable {
        /// ⌥ alone: hold to dictate, double-tap for hands-free (next ⌥ press finishes). Needs Input Monitoring.
        case option
        /// The `hotkey` combination (default ⌥Space): hold to dictate. Needs no permission; also the fallback.
        case hotkeyCombination
    }

    /// A global hotkey as a virtual key code plus Carbon modifier flags.
    public struct Hotkey: Codable, Equatable, Sendable {
        public var keyCode: UInt32
        public var carbonModifiers: UInt32

        public init(keyCode: UInt32, carbonModifiers: UInt32) {
            self.keyCode = keyCode
            self.carbonModifiers = carbonModifiers
        }

        /// ⌥ Space: kVK_Space (49) with optionKey (0x0800).
        public static let optionSpace = Hotkey(keyCode: 49, carbonModifiers: 0x0800)

        /// Human-readable form, e.g. "⌥Space". Modifier order follows macOS convention (⌃⌥⇧⌘).
        public var displayName: String {
            var name = ""
            if carbonModifiers & 0x1000 != 0 { name += "⌃" }
            if carbonModifiers & 0x0800 != 0 { name += "⌥" }
            if carbonModifiers & 0x0200 != 0 { name += "⇧" }
            if carbonModifiers & 0x0100 != 0 { name += "⌘" }
            let keys: [UInt32: String] = [49: "Space", 53: "Esc", 36: "Return", 48: "Tab"]
            return name + (keys[keyCode] ?? "Key \(keyCode)")
        }
    }

    public var processingMode: ProcessingMode
    public var dictationTrigger: DictationTrigger
    public var hotkey: Hotkey
    /// Recording stops automatically after this many seconds.
    public var maxRecordingSeconds: Double
    /// Developer option, off by default: keep each recording as a WAV in
    /// `~/Library/Application Support/VoiceFlow/debug-recordings/` for audio-quality checks and benchmarks.
    /// Not exposed in the menu; set in settings.json.
    public var saveRecordingsForDebugging: Bool
    /// `STTModel.id` from the catalog.
    public var sttModelID: String
    /// Bias Whisper toward developer vocabulary via its initial prompt (decisive on real speech, ACCURACY.md §5.5).
    public var useVocabularyPrompt: Bool
    /// Unload the STT model after this many idle seconds (0 = unload right after each dictation).
    public var sttUnloadAfterSeconds: Double
    /// Paste into the app focused when the transcript is ready (default) or only into the app focused at key press.
    public var pasteInto: InsertionPolicy.PasteTarget

    public static let `default` = Settings(processingMode: .fast, hotkey: .optionSpace, maxRecordingSeconds: 120)

    public init(processingMode: ProcessingMode, hotkey: Hotkey, maxRecordingSeconds: Double,
                saveRecordingsForDebugging: Bool = false, sttModelID: String = STTModel.mediumEnQ8.id,
                useVocabularyPrompt: Bool = true, sttUnloadAfterSeconds: Double = 300,
                pasteInto: InsertionPolicy.PasteTarget = .currentApp, dictationTrigger: DictationTrigger = .option) {
        self.pasteInto = pasteInto
        self.dictationTrigger = dictationTrigger
        self.processingMode = processingMode
        self.hotkey = hotkey
        self.maxRecordingSeconds = maxRecordingSeconds
        self.saveRecordingsForDebugging = saveRecordingsForDebugging
        self.sttModelID = sttModelID
        self.useVocabularyPrompt = useVocabularyPrompt
        self.sttUnloadAfterSeconds = sttUnloadAfterSeconds
    }

    /// The configured model, or the default if the configured id isn't in the catalog.
    public var sttModel: STTModel { STTModel.model(id: sttModelID) ?? .mediumEnQ8 }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings.default
        processingMode = (try? c.decodeIfPresent(ProcessingMode.self, forKey: .processingMode)) ?? d.processingMode
        dictationTrigger = (try? c.decodeIfPresent(DictationTrigger.self, forKey: .dictationTrigger)) ?? d.dictationTrigger
        hotkey = (try? c.decodeIfPresent(Hotkey.self, forKey: .hotkey)) ?? d.hotkey
        let seconds = (try? c.decodeIfPresent(Double.self, forKey: .maxRecordingSeconds)) ?? d.maxRecordingSeconds
        maxRecordingSeconds = (1...600).contains(seconds) ? seconds : d.maxRecordingSeconds
        saveRecordingsForDebugging = (try? c.decodeIfPresent(Bool.self, forKey: .saveRecordingsForDebugging)) ?? d.saveRecordingsForDebugging
        let modelID = (try? c.decodeIfPresent(String.self, forKey: .sttModelID)) ?? d.sttModelID
        sttModelID = STTModel.model(id: modelID) != nil ? modelID : d.sttModelID
        useVocabularyPrompt = (try? c.decodeIfPresent(Bool.self, forKey: .useVocabularyPrompt)) ?? d.useVocabularyPrompt
        let unload = (try? c.decodeIfPresent(Double.self, forKey: .sttUnloadAfterSeconds)) ?? d.sttUnloadAfterSeconds
        sttUnloadAfterSeconds = (0...86_400).contains(unload) ? unload : d.sttUnloadAfterSeconds
        pasteInto = (try? c.decodeIfPresent(InsertionPolicy.PasteTarget.self, forKey: .pasteInto)) ?? d.pasteInto
    }
}
