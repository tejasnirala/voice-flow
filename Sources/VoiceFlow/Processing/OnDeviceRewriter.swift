import Foundation
import os
import VoiceFlowCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Smart Mode rewriting with Apple's on-device foundation model (macOS 26+, Apple Intelligence enabled). Runs on-device
/// in a system process: no model files, no network, no memory in VoiceFlow. Every rewrite is checked by `RewriteGuard`
/// before use (docs/ACCURACY.md §6).
enum OnDeviceRewriter {
    /// nil when available; otherwise why Smart Mode can't be used.
    static var unavailableReason: String? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return nil
            case .unavailable(.appleIntelligenceNotEnabled): return "turn on Apple Intelligence in System Settings"
            case .unavailable(.deviceNotEligible): return "this Mac doesn't support Apple Intelligence"
            case .unavailable(.modelNotReady): return "Apple's on-device model is still downloading"
            case .unavailable: return "Apple's on-device model is unavailable"
            }
        }
        #endif
        return "requires macOS 26 or later"
    }

    /// A session prewarmed at recording start, used by the next rewrite with the same instructions. Using the prewarmed
    /// session itself (not a new one) saves 0.12–0.31 s per rewrite (docs/PERFORMANCE.md §5.4). Still one session per
    /// dictation: it is taken once and never reused, so nothing carries over between dictations.
    private static let warmSession = OSAllocatedUnfairLock<(instructions: String, session: AnyObject)?>(uncheckedState: nil)

    /// Loads the model and prepares a session for `prompt` (called when recording starts).
    static func prewarm(prompt: RewritePrompt) {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), unavailableReason == nil {
            let instructions = prompt.instructions
            let session = LanguageModelSession(instructions: instructions)
            session.prewarm()
            warmSession.withLockUnchecked { $0 = (instructions, session) }
        }
        #endif
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private static func takeSession(instructions: String) -> LanguageModelSession {
        let warm = warmSession.withLockUnchecked { state -> LanguageModelSession? in
            defer { state = nil }
            guard let state, state.instructions == instructions else { return nil }
            return state.session as? LanguageModelSession
        }
        return warm ?? LanguageModelSession(instructions: instructions)
    }
    #endif

    enum RewriteError: LocalizedError {
        case unavailable(String)
        case timedOut
        var errorDescription: String? {
            switch self {
            case .unavailable(let reason): "Smart Mode unavailable: \(reason)"
            case .timedOut: "Smart Mode timed out"
            }
        }
    }

    /// Rewrites `text` with a fresh session (no carry-over between dictations), greedy decoding, bounded length and time.
    static func rewrite(_ text: String, prompt: RewritePrompt, timeout: Duration = .seconds(5)) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if let reason = unavailableReason { throw RewriteError.unavailable(reason) }
            let maxTokens = text.split(whereSeparator: \.isWhitespace).count * 3 + 32
            return try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask {
                    let session = takeSession(instructions: prompt.instructions)
                    let response = try await session.respond(
                        to: text, options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: maxTokens))
                    return response.content
                }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    throw RewriteError.timedOut
                }
                let first = try await group.next()!
                group.cancelAll()
                return first
            }
        }
        #endif
        throw RewriteError.unavailable(unavailableReason ?? "unavailable")
    }
}
