// swift-tools-version: 6.0
import PackageDescription

// VoiceFlow is built with SwiftPM only (no Xcode project) so it builds with the
// Command Line Tools. `scripts/build-app.sh` wraps the executable in a .app bundle.
//
// Targets:
//   VoiceFlowCore — platform-independent logic (state machine, settings, audio gate, STT model
//                   catalog, transcript guard, accuracy scoring). No AppKit/AVFoundation; unit-tested.
//   VoiceFlow     — the menu-bar app: OS/hardware boundaries (hotkey, audio, permissions,
//                   insertion, UI). Never loads whisper.cpp itself.
//   voiceflow-stt — speech helper process: whisper.cpp (Core ML / Metal), started on demand, exits when idle.
//   vf-bench      — developer tool: scores STT benchmark results against the corpus.
//   whisper       — prebuilt whisper.cpp framework. Run `scripts/fetch-deps.sh` first; the
//                   package doesn't resolve without Vendor/whisper.xcframework.
let package = Package(
    name: "VoiceFlow",
    platforms: [.macOS(.v14)],
    targets: [
        .binaryTarget(name: "whisper", path: "Vendor/whisper.xcframework"),
        .target(name: "VoiceFlowCore"),
        .executableTarget(name: "VoiceFlow", dependencies: ["VoiceFlowCore"]),
        // The only process that loads whisper.cpp; embedded in VoiceFlow.app/Contents/MacOS and started on demand.
        .executableTarget(
            name: "voiceflow-stt",
            dependencies: ["VoiceFlowCore", "whisper"],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .executableTarget(name: "vf-bench", dependencies: ["VoiceFlowCore"]),
        .testTarget(name: "VoiceFlowCoreTests", dependencies: ["VoiceFlowCore"]),
        // App-level tests for AppKit boundaries that can run without hardware (e.g. private pasteboards).
        .testTarget(name: "VoiceFlowTests", dependencies: ["VoiceFlow"]),
    ]
)
