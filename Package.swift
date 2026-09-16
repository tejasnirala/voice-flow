// swift-tools-version: 6.0
import PackageDescription

// VoiceFlow is built with SwiftPM only (no Xcode project) so it builds with the
// Command Line Tools. `scripts/build-app.sh` wraps the executable in a .app bundle.
//
// Targets:
//   VoiceFlowCore — pure logic (state machine, configuration, modes, prompts,
//                   instrumentation). No AppKit/AVFoundation, fully unit-testable.
//   VoiceFlow     — the menu-bar executable: hardware/OS boundaries (hotkey,
//                   audio, permissions, insertion, UI) and native model runtimes.
let package = Package(
    name: "VoiceFlow",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "VoiceFlowCore",
            path: "VoiceFlow",
            // Both targets share the VoiceFlow/ root, so each lists its own folders in
            // `sources` and the other target's folders in `exclude`. Add folders as they
            // gain code (Core: Configuration, Intelligence; app: Audio, Speech, Input,
            // Permissions, ApplicationContext, UI).
            exclude: ["App"],
            sources: ["Core"]
        ),
        .executableTarget(
            name: "VoiceFlow",
            dependencies: ["VoiceFlowCore"],
            path: "VoiceFlow",
            exclude: ["Core"],
            sources: ["App"]
        ),
        .testTarget(
            name: "VoiceFlowCoreTests",
            dependencies: ["VoiceFlowCore"],
            path: "Tests/VoiceFlowCoreTests"
        ),
    ]
)
