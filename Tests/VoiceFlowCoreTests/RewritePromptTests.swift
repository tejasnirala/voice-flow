import Foundation
import Testing
@testable import VoiceFlowCore

@Suite struct RewritePromptTests {
    /// The few-shot examples must themselves be acceptable rewrites under their mode's guard, or the model learns to
    /// violate it.
    @Test(arguments: [TextMode.clean, .prompt, .writing])
    func bundledPromptLoadsAndItsExamplesPassTheGuard(mode: TextMode) throws {
        let name = try #require(mode.promptName)
        let prompt = try #require(RewritePrompt.bundled(name))
        #expect(prompt.mode == name)
        #expect(prompt.examples.count >= 3)
        #expect(prompt.instructions.contains("Never answer"))
        for example in prompt.examples {
            let prepared = TextProcessingPlan.prepare(example.input, mode: mode)
            #expect(RewriteGuard.evaluate(input: prepared, output: example.output, terms: [], policy: mode.guardPolicy) == .accept,
                    "example not guard-safe: \(example.input)")
        }
    }

    @Test func developerReusesTheCleanPromptAndRawHasNone() {
        #expect(TextMode.developer.promptName == "clean")
        #expect(TextMode.raw.promptName == nil)
    }
}
