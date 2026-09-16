# Environment

Inspected 2026-09-16 (Phase 0). All benchmark numbers in this repo come from this machine.

| Item | Value |
|---|---|
| Machine | MacBook Air (Mac16,13) |
| Chip | Apple M4 — 10 CPU cores (4 performance + 6 efficiency), 10-core GPU, Metal 4 |
| RAM | 16 GB unified memory |
| Disk | 460 GB APFS, ~272 GB free |
| macOS | 27.0 (build 26A5425a), Darwin 27.0.0, arm64 |
| Swift | Apple Swift 6.4 (swiftlang-6.4.0.34.1), target arm64-apple-macosx27.0 |
| Xcode | **Not installed** — Command Line Tools only (`/Library/Developer/CommandLineTools`) |
| SDKs | MacOSX 26, 26.5, 27.0 |
| Test frameworks | Swift Testing (in CLT); XCTest not available |
| C/C++ | Apple clang 21.0.0 |
| Metal compiler (`xcrun metal`) | Not available (requires Xcode) |
| CMake | Not installed |
| Rust | Not installed |
| Python | 3.13.0 (pyenv) — not used by VoiceFlow |
| Homebrew | 6.0.18 |
| git / gh | 2.54.0 / installed |
| Ollama | Not installed |

## Audio input devices

| Device | Channels | Sample rate | Note |
|---|---|---|---|
| iPhone microphone (Continuity) | 1 | 48 kHz | **Current system default input** |
| MacBook Air Microphone | 1 | 48 kHz | Built-in |
| AirPods Pro 3 | 1 | 24 kHz | Bluetooth; switching to a mic profile adds latency |
| Microsoft Teams Audio | 1 | 48 kHz | Virtual device |

Implication: recording-startup latency depends on the input device. Phase 3 measures each one.
VoiceFlow follows the system default input unless configured otherwise.

## Consequences of "Command Line Tools only"

- The project is a **SwiftPM package**. `scripts/build-app.sh` assembles `VoiceFlow.app`.
- `swift test` needs the Swift Testing macro plugin path passed explicitly → `scripts/test.sh`.
- Metal shaders can't be precompiled into a `.metallib`. whisper.cpp/llama.cpp prebuilt
  frameworks embed Metal source and compile it at runtime. That costs ~15 s on the first load
  per new binary, then the OS cache makes it ~0.1 s (measured, see `benchmarks/stt.md`).
- MLX-Swift can't be built from source (its SwiftPM build needs Xcode's Metal toolchain).
