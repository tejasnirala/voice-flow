import Testing
@testable import VoiceFlowCore

@Suite struct ListScaffoldTests {
    let input = "There are two things that I might need is one which is a local testing on each mode. The second point will be to get it fixed if any issue is found."
    let list = "There are two things that I might need:\n- Local testing on each mode.\n- Get it fixed if any issue is found."

    @Test(arguments: [RewriteGuard.Policy.strict, .contentPreserving])
    func spokenEnumerationMayBecomeAList(policy: RewriteGuard.Policy) {
        #expect(RewriteGuard.evaluate(input: input, output: list, terms: [], policy: policy) == .accept)
    }

    @Test(arguments: [RewriteGuard.Policy.strict, .contentPreserving])
    func firstSecondThirdSteps(policy: RewriteGuard.Policy) {
        let input = "first run the migration then second restart the worker and third check the logs"
        let output = "- Run the migration.\n- Restart the worker.\n- Check the logs."
        #expect(RewriteGuard.evaluate(input: input, output: output, terms: [], policy: policy) == .accept)
    }

    @Test(arguments: [RewriteGuard.Policy.strict, .contentPreserving])
    func countingWordsMayOnlyGoWhenAListIsMade(policy: RewriteGuard.Policy) {
        // No list: dropping "the second point will be" is content loss.
        let flat = "There are two things that I might need: local testing on each mode, and get it fixed if any issue is found."
        #expect(RewriteGuard.evaluate(input: input, output: flat, terms: [], policy: policy) != .accept)
        // A single bullet isn't a list.
        #expect(RewriteGuard.evaluate(input: "the first step is to run the migration",
                                      output: "- Run the migration.", terms: [], policy: policy) != .accept)
    }

    @Test(arguments: [RewriteGuard.Policy.strict, .contentPreserving])
    func contentBeforeAnItemIsNotScaffold(policy: RewriteGuard.Policy) {
        // "customer" and "admin" aren't counting words: removing them changes meaning.
        let input = "the first customer is blocked and the second admin is locked out"
        let output = "- Is blocked.\n- Is locked out."
        #expect(RewriteGuard.evaluate(input: input, output: output, terms: [], policy: policy) != .accept)
        // Counting words must be in the removed run ("we need" alone isn't scaffolding).
        #expect(RewriteGuard.evaluate(input: "we need tests and we need docs", output: "- Tests\n- Docs", terms: [], policy: policy) != .accept)
    }

    @Test func developerFormattingKeepsLinesAndBullets() {
        #expect(DeveloperFormatter.format("Two steps:\n- Edit dot env.\n- Run npm install dash dash save.")
                == "Two steps:\n- Edit .env.\n- Run npm install --save.")
        let (text, verdict) = TextProcessingPlan.finalText(
            prepared: "First add the key to .env and second run npm install --save.",
            rewrite: "- Add the key to .env.\n- Run npm install --save.", terms: [], mode: .developer)
        #expect(verdict == .accept)
        #expect(text == "- Add the key to .env.\n- Run npm install --save.")
    }

    @Test(arguments: [RewriteGuard.Policy.strict, .contentPreserving])
    func theOtherIs(policy: RewriteGuard.Policy) {
        let input = "I have two concerns the first is the migration time and the other is that we have no rollback plan"
        #expect(RewriteGuard.evaluate(input: input, output: "I have two concerns:\n- The migration time.\n- We have no rollback plan.",
                                      terms: [], policy: policy) == .accept)
        let meaningful = "the first service is up and the other service is down"
        #expect(RewriteGuard.evaluate(input: meaningful, output: "- Service is up.\n- Service is down.",
                                      terms: [], policy: policy) != .accept)
    }

    @Test func ownerDictationInCleanMode() {
        let input = "I think in the clean mode as well we are very good to go. There are two things that I might need is one which is a local testing on each mode. The second point will be to get it fixed if any issues is found and if any bug is left out."
        let output = "I think in the clean mode as well we are very good to go. There are two things I might need:\n- Local testing on each mode.\n- Get it fixed if any issues is found and if any bug is left out."
        #expect(RewriteGuard.evaluate(input: input, output: output, terms: [], policy: .strict) == .accept)
        // "that" may be deleted, never replaced.
        #expect(RewriteGuard.evaluate(input: "check that the pods are healthy", output: "Check which pods are healthy.",
                                      terms: [], policy: .strict) != .accept)
    }
}
