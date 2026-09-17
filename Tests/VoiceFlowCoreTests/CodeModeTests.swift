import Foundation
import Testing
@testable import VoiceFlowCore

@Suite struct CodeModeTests {
    func code(_ s: String) -> String { TextProcessingPlan.prepare(s, mode: .code) }

    @Test(arguments: [
        ("Git status.", "git status"),
        ("um git checkout dash b feature slash login", "git checkout -b feature/login"),
        ("npm install dash dash save dev", "npm install --save dev"),
        ("rm dash rf node underscore modules", "rm -rf node_modules"),
        ("const user equals await get user open paren id close paren", "const user = await get user(id)"),
        ("const user equals await camel case get user by id open paren id close paren", "const user = await getUserById(id)"),
        ("if x triple equals null open curly return close curly", "if x === null {return}"),
        ("if open paren x close paren", "if (x)"),
        ("ls slash usr slash local", "ls /usr/local"),
        ("src slash app dot tsx", "src/app.tsx"),
        ("Kube control get pods dash n staging.", "kubectl get pods -n staging"),
        ("curl localhost colon 3000 slash api slash users", "curl localhost:3000/api/users"),
        ("export snake case database url equals quote postgres quote", "export database_url = \"postgres\""),
        ("cd dot dot slash src", "cd ../src"),
        ("echo the build is done", "echo the build is done"),
    ])
    func formatsSpokenCode(input: String, expected: String) {
        #expect(code(input) == expected)
    }

    @Test func codeModeNeverUsesTheModel() {
        #expect(!TextMode.code.usesModel(processing: .smart))
        #expect(TextMode.code.promptName == nil)
    }
}

@Suite struct UserDictionaryTests {
    let dictionary = UserDictionary(terms: ["Supabase", "tRPC"],
                                    replacements: [.init(spoken: "voice flow", written: "VoiceFlow"),
                                                   .init(spoken: "kube control", written: "kubectl")])

    @Test func appliesReplacementsAndTermCasingInEveryModeButRaw() {
        let input = "we store voice flow data in supabase and call it over trpc, then kube control apply"
        #expect(TextProcessingPlan.prepare(input, mode: .raw, dictionary: dictionary) == input)
        #expect(TextProcessingPlan.prepare(input, mode: .clean, dictionary: dictionary)
                == "We store VoiceFlow data in Supabase and call it over tRPC, then kubectl apply.")
    }

    @Test func keepsPunctuationLinesAndWordBoundaries() {
        #expect(dictionary.apply(to: "- Use supabase.\n- Not supabaseClient") == "- Use Supabase.\n- Not supabaseClient")
        #expect(dictionary.apply(to: "voice, flow") == "voice, flow")
    }

    @Test func speechPromptAndProtectedTerms() {
        #expect(dictionary.speechPrompt(base: "Next.js, React") == "Next.js, React, Supabase, tRPC")
        #expect(UserDictionary.empty.speechPrompt(base: "Next.js") == "Next.js")
        #expect(dictionary.protectedTerms.contains("kubectl"))
    }

    @Test func tolerantLoading() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = UserDictionary.fileURL(in: dir)
        #expect(UserDictionary.load(from: url) == .empty)
        try Data(#"{"terms": ["Supabase", " "], "replacements": "oops", "future": 1}"#.utf8).write(to: url)
        #expect(UserDictionary.load(from: url) == UserDictionary(terms: ["Supabase"], replacements: []))
        try Data("not json".utf8).write(to: url)
        #expect(UserDictionary.load(from: url) == .empty)
        try Data(UserDictionary.template.utf8).write(to: url)
        #expect(UserDictionary.load(from: url).replacements.count == 1)
    }
}
