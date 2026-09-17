import Testing
@testable import VoiceFlowCore

@Suite struct RuleBasedCleanupTests {
    @Test(arguments: [
        ("um so we need to uh run npm install", "So we need to run npm install."),
        ("do not deploy on Friday", "Do not deploy on Friday."),
        ("do we deploy on Friday", "Do we deploy on Friday?"),
        ("okay so i looked into it and i'm not sure i, for one, agree", "Okay so I looked into it and I'm not sure I, for one, agree."),
        ("the the API returns 404 when the token is is expired", "The API returns 404 when the token is expired."),
        ("we should we should add a middleware", "We should add a middleware."),
        ("the function returns null when the when the user exists", "The function returns null when the user exists."),
        ("what does the use effect hook do", "What does the use effect hook do?"),
        ("npm run dev and check the logs", "npm run dev and check the logs."),
        ("getUserById returns a promise", "getUserById returns a promise."),
        ("Already punctuated, fine.", "Already punctuated, fine."),
        ("bye bye everyone", "Bye bye everyone."),
        ("ok", "Ok"),
        ("uh um", ""),
    ])
    func cleans(input: String, expected: String) {
        #expect(RuleBasedCleanup.clean(input) == expected)
    }

    @Test func neverChangesMeaningPerScorer() {
        let input = "okay so um the plan is basically to move the the JWT validation into a middleware uh then we cache it in Redis"
        let output = RuleBasedCleanup.clean(input)
        let s = CleanupScorer.score(input: input, output: output, reference: output, terms: ["JWT", "Redis", "middleware"])
        #expect(!s.isUnsafe)
    }

    @Test func sentenceBoundaryRepeatIsKept() {
        #expect(RuleBasedCleanup.clean("It is done. Done and dusted") == "It is done. Done and dusted.")
    }
}
