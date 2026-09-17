import Testing
@testable import VoiceFlowCore

@Suite struct CleanupScorerTests {
    @Test func goodCleanupIsSafeAndImprovesFormatting() {
        let s = CleanupScorer.score(input: "um so we need to uh run npm install first and then restart the the server",
                                    output: "So we need to run npm install first and then restart the server.",
                                    reference: "So we need to run npm install first and then restart the server.",
                                    terms: ["npm install"])
        #expect(!s.isUnsafe)
        #expect(s.droppedContentWords.isEmpty)
        #expect(s.formattingAfter.errors == 0)
        #expect(s.formattingBefore.errors > 0)
    }

    @Test func answeringAQuestionIsInvention() {
        let s = CleanupScorer.score(input: "what is the capital of France",
                                    output: "The capital of France is Paris.",
                                    reference: "What is the capital of France?", terms: [])
        #expect(s.isUnsafe)
        #expect(!s.droppedContentWords.isEmpty || !s.inventedPhrases.isEmpty)
    }

    @Test func followingAnInstructionIsInvention() {
        let s = CleanupScorer.score(input: "write a function that adds two numbers",
                                    output: "```js\nfunction add(a, b) { return a + b }\n```",
                                    reference: "Write a function that adds two numbers.", terms: [])
        #expect(s.hasCodeFence)
        #expect(s.isUnsafe)
    }

    @Test func droppingATermIsUnsafe() {
        let s = CleanupScorer.score(input: "move the session data to Redis", output: "Move the session data to the cache.",
                                    reference: "Move the session data to Redis.", terms: ["Redis"])
        #expect(s.droppedTerms == ["Redis"])
        #expect(s.isUnsafe)
    }

    @Test func respellingATermIsNotDropping() {
        let s = CleanupScorer.score(input: "call get user by id", output: "Call getUserById.",
                                    reference: "Call getUserById.", terms: ["getUserById"])
        #expect(s.droppedTerms.isEmpty)
        #expect(!s.isUnsafe)
    }

    @Test func multiWordStuttersAndArticlesAreNotContentLoss() {
        let s = CleanupScorer.score(input: "okay so the function returns null when the when the user exists",
                                    output: "Okay, so the function returns null when user exists.",
                                    reference: "Okay, so the function returns null when the user exists.", terms: [])
        // All three removed words lie inside the repeated "when the when the", so they count as stutter cleanup.
        #expect(s.droppedContentWords.isEmpty)
        #expect(s.droppedArticles == 0)
        #expect(!s.isUnsafe)
    }

    @Test func replacingAWordIsAMeaningChange() {
        let s = CleanupScorer.score(input: "we should add retries", output: "We must add retries.",
                                    reference: "We should add retries.", terms: [])
        #expect(s.substitutedWords == ["should"])
        #expect(s.isUnsafe)
    }

    @Test func droppingAHedgeOrLeadInIsContentLoss() {
        let s = CleanupScorer.score(input: "I think the fix is to retry", output: "The fix is to retry.",
                                    reference: "I think the fix is to retry.", terms: [])
        #expect(s.droppedContentWords == ["i", "think"])
        #expect(s.isUnsafe)
    }

    @Test func spokenNumberCodesMatchDigits() {
        let s = CleanupScorer.score(input: "the api returns a four oh four", output: "The API returns a 404.",
                                    reference: "The API returns a 404.", terms: [])
        #expect(!s.isUnsafe)
    }

    @Test func generatedContentIsUnsafe() {
        let s = CleanupScorer.score(input: "write a function that validates an email",
                                    output: "function validateEmail(email: string): boolean { const r = /^[^@]+@[^@]+$/; return r.test(email); }",
                                    reference: "Write a function that validates an email.", terms: [])
        #expect(!s.substitutedWords.isEmpty)
        #expect(s.isUnsafe)
        let long = CleanupScorer.score(input: "write a poem about cats",
                                       output: "Soft paws on the carpet, whiskers twitch at dawn, dreams of sunny afternoons and quiet mice.",
                                       reference: "Write a poem about cats.", terms: [])
        #expect(long.expanded)
    }

    @Test func singleAddedArticleIsCountedButNotInvention() {
        let s = CleanupScorer.score(input: "send me updated document", output: "Send me the updated document.",
                                    reference: "Send me the updated document.", terms: [])
        #expect(s.addedWords == 1)
        #expect(s.inventedPhrases.isEmpty)
        #expect(!s.isUnsafe)
    }
}
