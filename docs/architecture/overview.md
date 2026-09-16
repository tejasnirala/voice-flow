# Architecture overview

## Guiding principle
Use the minimum computation necessary. Everything is event-driven. Nothing runs, loads, or
records unless the user is dictating.

## Technology decisions

| Concern | Decision | Rejected alternatives (why) |
|---|---|---|
| Language | **Swift 6** (strict concurrency) | Obj-C: no advantage, less safe. Rust/C++: every macOS API (AppKit, AVFoundation, Carbon hotkeys, NSPasteboard, CGEvent, AX) would need FFI, and the inference cores are already C/C++ libraries callable from Swift directly. |
| UI | **AppKit `NSStatusItem` + `NSMenu`** | SwiftUI `MenuBarExtra`: pulls in the SwiftUI runtime and more memory for a plain menu. A SwiftUI settings window may be added later, loaded lazily. |
| Build | **SwiftPM + `scripts/build-app.sh`** | Xcode project: Xcode isn't installed, and the owner chose not to install it. |
| Hotkey | **Carbon `RegisterEventHotKey`** (press + release events) | CGEventTap: needs Input Monitoring/Accessibility and sees every keystroke. NSEvent global monitor: can't swallow the key and needs Accessibility. |
| Audio | **AVAudioEngine** input tap → in-memory 16 kHz mono Float32 | Core Audio AUHAL: lower level, more code. Only if Phase 3 measures AVAudioEngine start latency as a problem. |
| STT | **whisper.cpp** (prebuilt xcframework, Metal). Model chosen in Phase 4 (base.en vs small.en) | MLX Whisper: Python runtime. WhisperKit: CoreML compile + heavier dependency chain. Apple SpeechTranscriber: strong zero-dependency option, kept as a benchmarked alternative (weaker on tech vocab in the first test). |
| LLM runtime | **llama.cpp**, in-process, lazily loaded | Ollama: localhost HTTP daemon (spec forbids a server, idle RAM). MLX: can't build without Xcode; prebuilt Cmlx.xcframework is ~200 MB zipped. |
| LLM model | **Qwen2.5-1.5B-Instruct Q4_K_M** as starting candidate (Phase 7 compares 0.5B / Gemma 3 1B / Llama 3.2 1B) | Larger models: latency/RAM not justified for a text-transform task. |
| Insertion | **Pasteboard snapshot → set text → CGEvent ⌘V → restore** | AX `kAXSelectedText` set: fails in Electron apps, terminals, many web views. Synthetic Unicode typing: slow on long text, breaks IME/autocomplete. |
| Config | JSON file in Application Support (Codable) | UserDefaults: fine too, but a JSON file is inspectable and portable. |

## Components & boundaries

```
VoiceFlowCore (pure Swift, unit-tested)          VoiceFlow executable (OS / hardware / native libs)
├── Core/            PipelineState, errors,       ├── App/                 entry point, AppDelegate, pipeline wiring
│                    PerformanceMonitor spans     ├── UI/                  NSStatusItem menu
├── Configuration/   AppConfiguration (Codable)   ├── Input/               HotkeyManager, TextInsertionService
└── Intelligence/    ProcessingMode, prompt       ├── Audio/               AudioRecorder (AVAudioEngine)
                     loading, rule-based          ├── Speech/              SpeechToTextEngine → WhisperEngine
                     cleanup, TranscriptProcessor ├── Permissions/         mic + Accessibility status
                     protocol                     └── ApplicationContext/  ActiveApplicationProvider
```

Protocols exist only at hardware, native-library, and model boundaries:
`AudioRecorder`, `SpeechToTextEngine`, `TranscriptProcessor`, `TextInsertionService`,
`ActiveApplicationProvider`, `HotkeyManager`, `ModelManager`. These are also where test mocks go.

## Pipeline & state machine

```
IDLE ──hotkey down──▶ RECORDING ──hotkey up──▶ TRANSCRIBING ──▶ PROCESSING* ──▶ INSERTING ──▶ IDLE
  ▲                        │ silence/too short                      (*skipped in Fast Mode)
  └────────────────────────┘
ANY ──error──▶ ERROR ──▶ IDLE          ANY ACTIVE ──cancel──▶ CANCELLED ──▶ IDLE
```

- The pipeline is a single `@MainActor` coordinator owning the state. Inference runs off the
  main actor (a dedicated actor per engine) so the menu stays responsive.
- One request at a time. A hotkey press during processing is ignored (or cancels, decided in Phase 2).

## Model lifecycle (hypothesis; decided by measurement in Phases 6 and 11)
Phase 0 numbers: whisper base.en Metal load 0.11 s, small.en 0.23–0.34 s once shaders are cached.
Qwen 1.5B load ~0.15–0.3 s. Loading is cheap, so **Strategy A/B** (load on demand, maybe keep
Whisper warm for N minutes after use, then release) looks viable without a large latency cost.
To be confirmed in-app.

## Startup
Load config → create status item → register hotkey → done. No models, no audio engine, no
GPU work at launch.
