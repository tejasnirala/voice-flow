/// The deterministic part of turning a raw STT transcript into the text that gets pasted, per text mode.
public enum TextProcessingPlan {
    /// Applied before any optional model rewrite (after Whisper artifact removal):
    /// Raw → unchanged; Clean, Prompt, Writing → rule-based cleanup; Developer → cleanup + spoken symbols and term casing.
    public static func prepare(_ transcript: String, mode: TextMode) -> String {
        switch mode {
        case .raw: transcript
        case .clean, .prompt, .writing: RuleBasedCleanup.clean(transcript)
        case .developer: DeveloperFormatter.format(RuleBasedCleanup.clean(transcript))
        }
    }

    /// Chooses between a model rewrite and the prepared text using the mode's guard policy.
    /// Developer output is re-formatted so the model can't undo symbol joins or term casing.
    public static func finalText(prepared: String, rewrite: String?, terms: [String], mode: TextMode = .clean)
        -> (text: String, verdict: RewriteGuard.Verdict?) {
        guard let rewrite else { return (prepared, nil) }
        let verdict = RewriteGuard.evaluate(input: prepared, output: rewrite, terms: terms, policy: mode.guardPolicy)
        switch verdict {
        case .accept:
            let text = tidy(rewrite)
            return (mode == .developer ? DeveloperFormatter.format(text) : text, verdict)
        case .reject:
            return (prepared, verdict)
        }
    }

    /// Layout-only fixes to an accepted rewrite: trailing spaces on lines, runs of blank lines, and a lone "- " bullet.
    static func tidy(_ text: String) -> String {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            String(line.reversed().drop { $0 == " " || $0 == "\t" }.reversed())
        }
        lines = lines.enumerated().filter { $0.offset == 0 || !($0.element.isEmpty && lines[$0.offset - 1].isEmpty) }.map(\.element)
        let joined = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let nonEmpty = joined.split(separator: "\n")
        if nonEmpty.count == 1, joined.hasPrefix("- ") { return String(joined.dropFirst(2)) }
        return joined
    }
}
