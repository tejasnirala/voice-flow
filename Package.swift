// swift-tools-version: 6.0
import PackageDescription

// VoiceFlow is built with SwiftPM only (no Xcode project) so it builds with the
// Command Line Tools. `scripts/build-app.sh` wraps the executable in a .app bundle.
//
// Targets:
//   VoiceFlowCore — platform-independent logic (state machine, settings, text
//                   processing, accuracy scoring). No AppKit/AVFoundation; unit-tested.
//   VoiceFlow     — the menu-bar app: OS/hardware boundaries (hotkey, audio,
//                   permissions, insertion, UI) and native inference runtimes.
//   vf-bench      — developer tool: scores STT benchmark results against the corpus.
//
// Native STT benchmark engines live in scripts/bench/ (compiled with swiftc against
// Vendor/whisper.xcframework) so a plain `swift build` never requires Vendor/.
let package = Package(
    name: "VoiceFlow",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "VoiceFlowCore"),
        .executableTarget(name: "VoiceFlow", dependencies: ["VoiceFlowCore"]),
        .executableTarget(name: "vf-bench", dependencies: ["VoiceFlowCore"]),
        .testTarget(name: "VoiceFlowCoreTests", dependencies: ["VoiceFlowCore"]),
    ]
)
