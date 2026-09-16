# Dependencies

Every dependency must answer **"why do we need this?"**

## Runtime (linked into / shipped with the app)

| Dependency | Version | Status | Why | Size |
|---|---|---|---|---|
| Apple frameworks: AppKit, Foundation, AVFoundation, Carbon (HIToolbox), CoreGraphics, ApplicationServices | OS | AppKit + Foundation in use | Native UI, audio, hotkey, events, pasteboard. Zero added weight | 0 |
| **whisper.cpp** (`whisper.xcframework`, includes ggml) | b5130 (release v1.9.4), SHA-256 `033a43b0…6f231a` | Fetched. Linked in Phase 4 | Local STT with Metal acceleration, C API callable from Swift, no daemon. Measured fastest acceptable option | 8.5 MB universal dylib (macOS slice; x86_64 can be stripped → ~4 MB) |
| **llama.cpp** | b11005 (release v0.4.1) candidate | Evaluated only | Local LLM for Smart Processing, in-process with Metal. Only loaded when enabled | TBD (Phase 7) |

No Swift packages. No package manager dependencies.

## Build / development only (never shipped)

| Tool | Why |
|---|---|
| Swift 6.4 toolchain (Command Line Tools) | Compiler, SwiftPM, Swift Testing |
| `codesign`, `security` (macOS) | Sign the app bundle |
| `curl`, `shasum`, `unzip` (macOS) | Fetch and verify runtimes and models |
| `say`, `afinfo` (macOS) | Generate and inspect benchmark audio |
| llama.cpp release binaries (`llama-bench`, `llama-completion`) | Phase 0 LLM benchmark only, kept in scratch space |

## Model files (data, not code; outside the bundle)

| Model | Source | Size | Status |
|---|---|---|---|
| ggml-tiny.en / base.en / small.en | huggingface.co/ggerganov/whisper.cpp | 74 MB / 141 MB / 466 MB | Downloaded for benchmarking |
| qwen2.5-1.5b-instruct-q4_k_m.gguf | huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF | 1.04 GiB | Downloaded for benchmarking |

## Considered and rejected
| Candidate | Reason |
|---|---|
| Ollama | Localhost daemon, idle memory; spec forbids a local server |
| MLX / mlx-swift | Needs Xcode to build Metal shaders; prebuilt Cmlx.xcframework ~200 MB zipped |
| MLX Whisper | Python runtime |
| WhisperKit | CoreML plus swift-transformers chain; whisper.cpp already meets latency |
| Electron / web UI / SwiftUI app shell | Weight; AppKit menu is enough |
| HotKey / KeyboardShortcuts Swift packages | ~50 lines of Carbon code do the same job |
