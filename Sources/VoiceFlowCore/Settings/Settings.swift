/// User settings persisted as JSON (`~/Library/Application Support/VoiceFlow/settings.json`).
///
/// Decoding is forward- and backward-tolerant: missing keys take their defaults and unknown keys are
/// ignored, so adding a setting never invalidates an existing file.
public struct Settings: Codable, Equatable, Sendable {
    public enum ProcessingMode: String, Codable, Sendable, CaseIterable {
        /// Audio → STT → paste. No LLM.
        case fast
        /// Clean and Developer modes also get an on-device Apple model rewrite checked by `RewriteGuard`.
        /// (Prompt and Writing always use the model.)
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
    /// Unload the STT model after this many idle seconds (0 = unload right after each dictation). Default 60 s: loading
    /// runs while the user speaks (0.3 s), so a cold dictation is as fast as a warm one, while each load/unload cycle
    /// leaks ~0.7 MB inside whisper.cpp; a minute keeps a burst of dictations on one load (PERFORMANCE.md §3.8).
    public var sttUnloadAfterSeconds: Double
    /// Paste into the app focused when the transcript is ready (default) or only into the app focused at key press.
    public var pasteInto: InsertionPolicy.PasteTarget
    /// How transcripts are turned into pasted text (Raw, Clean, Developer, Prompt, Writing, Code). With `modeByApp`, this
    /// is the mode for apps without a rule.
    public var textMode: TextMode
    /// Choose the text mode from the app receiving the dictation (`AppModePolicy`).
    public var modeByApp: Bool
    /// The owner's per-app modes by bundle ID; they override the built-in defaults.
    public var appModes: [String: TextMode]
    /// Show the floating pill while dictating.
    public var showIndicator: Bool
    /// Where the owner dragged the pill (window origin in screen coordinates); nil = bottom center of the main screen.
    public var indicatorPosition: IndicatorPosition?

    public struct IndicatorPosition: Codable, Equatable, Sendable {
        public var x: Double
        public var y: Double
        public init(x: Double, y: Double) { self.x = x; self.y = y }
    }

    public static let `default` = Settings(processingMode: .fast, hotkey: .optionSpace, maxRecordingSeconds: 120)

    public init(processingMode: ProcessingMode, hotkey: Hotkey, maxRecordingSeconds: Double,
                saveRecordingsForDebugging: Bool = false, sttModelID: String = STTModel.mediumEnQ8.id,
                useVocabularyPrompt: Bool = true, sttUnloadAfterSeconds: Double = 60,
                pasteInto: InsertionPolicy.PasteTarget = .currentApp, dictationTrigger: DictationTrigger = .option,
                textMode: TextMode = .clean, modeByApp: Bool = true, appModes: [String: TextMode] = [:],
                showIndicator: Bool = true, indicatorPosition: IndicatorPosition? = nil) {
        self.showIndicator = showIndicator
        self.indicatorPosition = indicatorPosition
        self.pasteInto = pasteInto
        self.textMode = textMode
        self.modeByApp = modeByApp
        self.appModes = appModes
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

    private enum LegacyKeys: String, CodingKey { case cleanupTranscripts }

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
        // Before Phase 8, `cleanupTranscripts: false` meant no cleanup: that's Raw mode now.
        let legacyCleanup = try? decoder.container(keyedBy: LegacyKeys.self).decodeIfPresent(Bool.self, forKey: .cleanupTranscripts)
        textMode = (try? c.decodeIfPresent(TextMode.self, forKey: .textMode)) ?? (legacyCleanup == false ? .raw : d.textMode)
        modeByApp = (try? c.decodeIfPresent(Bool.self, forKey: .modeByApp)) ?? d.modeByApp
        // Entries with an unknown mode are dropped individually, not the whole table.
        let rawAppModes = (try? c.decodeIfPresent([String: String].self, forKey: .appModes)) ?? [:]
        appModes = rawAppModes.compactMapValues(TextMode.init(rawValue:))
        showIndicator = (try? c.decodeIfPresent(Bool.self, forKey: .showIndicator)) ?? d.showIndicator
        indicatorPosition = (try? c.decodeIfPresent(IndicatorPosition.self, forKey: .indicatorPosition)) ?? nil
    }
}
