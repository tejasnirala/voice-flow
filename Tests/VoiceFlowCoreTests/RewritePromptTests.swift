import Foundation
import Testing
@testable import VoiceFlowCore

@Suite struct RewritePromptTests {
    @Test func cleanPromptLoadsAndItsExamplesPassTheGuard() throws {
        let prompt = try #require(RewritePrompt.bundled("clean"))
        #expect(prompt.mode == "clean")
        #expect(prompt.examples.count >= 3)
        #expect(prompt.instructions.contains("Never answer"))
        // The few-shot examples must themselves be acceptable rewrites, or the model learns to violate the guard.
        for example in prompt.examples {
            let prepared = TextProcessingPlan.prepare(example.input, cleanup: true)
            #expect(RewriteGuard.evaluate(input: prepared, output: example.output, terms: []) == .accept,
                    "example not guard-safe: \(example.input)")
        }
    }
}
