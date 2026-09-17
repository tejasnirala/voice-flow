/// The deterministic part of turning a raw STT transcript into the text that gets pasted.
public enum TextProcessingPlan {
    /// Applied to every transcript before any optional LLM rewrite: Whisper artifact removal, then (if enabled) the
    /// rule-based cleanup (hesitations, stutters, first-word capitalization, end punctuation).
    public static func prepare(_ transcript: String, cleanup: Bool) -> String {
        cleanup ? RuleBasedCleanup.clean(transcript) : transcript
    }

    /// Chooses between an LLM rewrite and the prepared text.
    public static func finalText(prepared: String, rewrite: String?, terms: [String])
        -> (text: String, verdict: RewriteGuard.Verdict?) {
        guard let rewrite else { return (prepared, nil) }
        let verdict = RewriteGuard.evaluate(input: prepared, output: rewrite, terms: terms)
        switch verdict {
        case .accept: return (rewrite.trimmingCharacters(in: .whitespacesAndNewlines), verdict)
        case .reject: return (prepared, verdict)
        }
    }
}
