import Testing
@testable import VoiceFlowCore

@Suite struct DeveloperCorrectionsTests {
    func dev(_ s: String) -> String { DeveloperFormatter.format(s) }

    /// Measured errors from the owner's recordings and common spoken forms.
    @Test(arguments: [
        ("Run kube control get pods to see which pods are crashing.", "Run kubectl get pods to see which pods are crashing."),
        ("increase the timeout in nginx.com", "increase the timeout in nginx.conf"),
        ("Increase the timeout in engine x dot conf.", "Increase the timeout in nginx.conf."),
        ("check the nginx.com file", "check the nginx.conf file"),
        ("We deploy it with a help chart.", "We deploy it with a Helm chart."),
        ("The use effect hook calls fetch orders when the page loads.", "The useEffect hook calls fetch orders when the page loads."),
        ("pass handleSubmit to the forms on submit prop", "pass handleSubmit to the forms onSubmit prop"),
        ("add an on key down handler", "add an onKeyDown handler"),
        ("The refresh access token function runs when the token expires.", "The refreshAccessToken function runs when the token expires."),
        ("write the fetch orders function first", "write the fetchOrders function first"),
        ("set database_url in the environment", "set DATABASE_URL in the environment"),
        ("export stripe_secret_key before starting", "export STRIPE_SECRET_KEY before starting"),
        ("add stripe_secret_key as an environment variable", "add STRIPE_SECRET_KEY as an environment variable"),
        ("Then gate rebase main before you push.", "Then git rebase main before you push."),
        ("open localhost colon 3000 in the browser", "open localhost:3000 in the browser"),
        ("the docs are on example dot com", "the docs are on example.com"),
        ("rename it to camel case get user by id", "rename it to getUserById"),
        ("call it snake case user session id", "call it user_session_id"),
    ])
    func corrects(input: String, expected: String) {
        #expect(dev(input) == expected)
    }

    /// The same trigger words in ordinary speech stay unchanged.
    @Test(arguments: [
        "We don't need help for now.",
        "Can you help install the printer?",
        "Go to nginx.com for the docs.",
        "The gate is closed, so check the gate status.",
        "Meet me at the gate.",
        "We use state funding for the project.",
        "I use hooks to hang my coat.",
        "Turn on submit mode and click.",
        "This is a pure function.",
        "The higher order function returns a function.",
        "We need to check the function.",
        "Use camel case for variable names.",
        "Convert all the column names to camelCase.",
        "Rename the variable to snake_case so it becomes user_session_id.",
        "The dot com bubble burst in 2000.",
        "My cube control panel is broken.",
        "Set the user_id column as the primary key.",
        "Please call support and get help.",
        "We met at the local host dot com event.",
        // Found in the owner's long-form transcript: the cue must not swallow the next clause.
        "Convert all the column names to camelCase, enable strict mode in tsconfig.json.",
        "Convert the names to camelCase enable strict mode in tsconfig.json.",
    ])
    func leavesOrdinarySpeechAlone(input: String) {
        #expect(dev(input) == input)
    }
}
