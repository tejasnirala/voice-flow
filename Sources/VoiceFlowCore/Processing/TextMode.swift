/// How a transcript is turned into the pasted text (spec §16).
public enum TextMode: String, Codable, Sendable, CaseIterable {
    /// The transcript as recognized (Whisper artifacts removed only).
    case raw
    /// Hesitations, stutters, capitalization, end punctuation (rules). Default.
    case clean
    /// Clean + spoken symbols and developer term casing (rules).
    case developer
    /// Spoken thoughts → a clear prompt for an AI assistant (on-device model, content-preserving guard).
    case prompt
    /// Polished prose (on-device model, content-preserving guard).
    case writing

    /// Whether the mode always uses the on-device model (Prompt, Writing). Clean and Developer use it only in Smart Mode;
    /// Raw never does.
    public var requiresModel: Bool { self == .prompt || self == .writing }

    /// Whether this mode rewrites with the on-device model under the given processing mode.
    public func usesModel(processing: Settings.ProcessingMode) -> Bool {
        switch self {
        case .raw: false
        case .clean, .developer: processing == .smart
        case .prompt, .writing: true
        }
    }

    /// The bundled prompt file (prompts/<name>.json). Developer reuses Clean: its formatting is deterministic.
    public var promptName: String? {
        switch self {
        case .raw: nil
        case .clean, .developer: "clean"
        case .prompt: "prompt"
        case .writing: "writing"
        }
    }

    public var displayName: String {
        switch self {
        case .raw: "Raw"
        case .clean: "Clean"
        case .developer: "Developer"
        case .prompt: "Prompt"
        case .writing: "Writing"
        }
    }

    /// Guard policy for model rewrites in this mode.
    public var guardPolicy: RewriteGuard.Policy {
        switch self {
        case .raw, .clean, .developer: .strict
        case .prompt, .writing: .contentPreserving
        }
    }
}
