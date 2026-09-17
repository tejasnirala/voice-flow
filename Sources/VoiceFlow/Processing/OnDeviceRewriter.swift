import Foundation
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

    /// Loads the model ahead of use (called when recording starts in Smart Mode).
    static func prewarm(prompt: RewritePrompt) {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), unavailableReason == nil {
            LanguageModelSession(instructions: prompt.instructions).prewarm()
        }
        #endif
    }

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
                    let session = LanguageModelSession(instructions: prompt.instructions)
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
