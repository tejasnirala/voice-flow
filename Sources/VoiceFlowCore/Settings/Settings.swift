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
    public var hotkey: Hotkey
    /// Recording stops automatically after this many seconds.
    public var maxRecordingSeconds: Double

    public static let `default` = Settings(processingMode: .fast, hotkey: .optionSpace, maxRecordingSeconds: 120)

    public init(processingMode: ProcessingMode, hotkey: Hotkey, maxRecordingSeconds: Double) {
        self.processingMode = processingMode
        self.hotkey = hotkey
        self.maxRecordingSeconds = maxRecordingSeconds
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings.default
        processingMode = (try? c.decodeIfPresent(ProcessingMode.self, forKey: .processingMode)) ?? d.processingMode
        hotkey = (try? c.decodeIfPresent(Hotkey.self, forKey: .hotkey)) ?? d.hotkey
        let seconds = (try? c.decodeIfPresent(Double.self, forKey: .maxRecordingSeconds)) ?? d.maxRecordingSeconds
        maxRecordingSeconds = (1...600).contains(seconds) ? seconds : d.maxRecordingSeconds
    }
}
