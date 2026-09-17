# Architecture

Phase 0 deliverable (spec §26). Measurements referenced here are in [`ACCURACY.md`](ACCURACY.md) and
[`PERFORMANCE.md`](PERFORMANCE.md). Nothing below is claimed without a measurement or an explicit
"expected/untested" label.

---

## 1. Machine

Inspected 2026-09-16.

| | |
|---|---|
| **Model** | MacBook Air (Mac16,13) |
| **CPU** | Apple M4: 10 cores (4 performance + 6 efficiency) |
| **GPU** | Apple M4 10-core GPU, Metal 4 |
| **RAM** | 16 GB unified memory |
| **macOS** | 27.0 (build 26A5425a) |
| **Architecture** | arm64 (Apple Silicon) |
| **Swift** | Apple Swift 6.4 (swiftlang-6.4.0.34.1) |
| **Xcode** | **Not installed.** Command Line Tools only (SDKs 26, 26.5, 27.0). Owner chose not to install Xcode |
| Disk | 460 GB APFS, ~272 GB free |
| Other tools | Homebrew 6.0.18, clang 21, git 2.54, gh, Python 3.13 (scripts only). No CMake, Rust or Ollama |
| Test frameworks | Swift Testing (in CLT). No XCTest |
| Audio inputs | MacBook Air mic (48 kHz), AirPods Pro 3 (24 kHz, Bluetooth), iPhone Continuity mic (48 kHz, **current default**), Teams virtual device |
| Apple speech | `SpeechAnalyzer`/`SpeechTranscriber` available on-device. en-US/en-GB/en-IN/… installed; hi-IN supported |

**Toolchain consequences:** SwiftPM-only build with a script-assembled `.app`. No offline Metal
compiler, so runtimes must ship Metal source (compiled at runtime and cached by macOS) or run on CPU/ANE.
MLX-Swift can't be built from source here.

---

## 2. Proposed stack

| Component | Choice | Status |
|---|---|---|
| **UI** | AppKit `NSStatusItem` + `NSMenu`. Optional tiny non-activating `NSPanel` recording indicator | Decided |
| **Audio** | `AVAudioEngine` input tap → `AVAudioConverter` → in-memory 16 kHz mono Float32 buffer. No files | Decided (start latency measured in Phase 3) |
| **Global hotkey** | Carbon `RegisterEventHotKey` (press + release events). Esc registered only while recording, for cancel | Decided |
| **STT runtime** | **whisper.cpp** (prebuilt `whisper.xcframework`, Metal) behind a `SpeechEngine` protocol. The same framework also runs **Parakeet** | Decided, confirmed by measurement (§4) |
| **STT model** | **Whisper medium.en q8_0 + developer vocabulary prompt** (alternate: large-v3-turbo q8_0 + prompt), §4.3 | Provisional; final at Phase 4 gate |
| **LLM runtime** | **llama.cpp**, in-process, lazily loaded, Smart Mode only | Provisional; MLX comparison in Phase 7 |
| **LLM model** | Qwen2.5-1.5B-Instruct Q4_K_M as the starting candidate | Provisional; compared in Phase 7 |
| **Text insertion** | Full pasteboard snapshot → set text (transient/concealed markers) → CGEvent ⌘V → restore if unchanged | Decided |
| **Storage** | Models: `~/Library/Application Support/VoiceFlow/models/<runtime>/`. Settings: `…/VoiceFlow/settings.json`. Logs: unified logging (`os.Logger`), no transcript content. Audio: memory only | Decided |
| **Testing** | Swift Testing unit tests on `VoiceFlowCore` (pure logic). Protocol-based fakes at hardware/model boundaries. Corpus benchmark (`vf-bench`) for STT quality | Decided |
| **Build** | SwiftPM + `scripts/build-app.sh` (assemble, embed linked frameworks, codesign) | Decided |

### Pipeline & state machine

```
IDLE ──⌥Space down──▶ RECORDING ──⌥Space up──▶ TRANSCRIBING ──▶ PROCESSING* ──▶ INSERTING ──▶ IDLE
                        │  Esc / too short / silent            (*Smart Mode only;
                        ▼                                        on LLM failure → insert raw STT)
                       IDLE
ANY ──failure──▶ ERROR (message shown; transcript kept on clipboard if it exists) ──▶ IDLE
```

- One `@MainActor` coordinator owns state and transitions. Tests enumerate every valid and invalid transition.
- Inference runs in dedicated actors (`SpeechEngine`, `LocalLLMEngine`) off the main thread. The menu stays responsive.
- **Never lose speech:** if insertion fails (no Accessibility permission, focus changed to another app,
  secure input field), the text stays on the clipboard and the menu/indicator says so.
- Duplicate hotkey presses while not IDLE are ignored. Recording has a max duration (default 120 s, configurable).

### Module layout (adapted from spec §24)

```
Sources/VoiceFlowCore/          (no AppKit/AVFoundation; unit-tested)
  State/        PipelineState, transitions
  Settings/     Settings model + persistence (Codable JSON)
  Speech/       TranscriptionResult, ModelManifest/ModelStatus, Accuracy/ (corpus, normalizer, scorer)
  Processing/   TextProcessor, DeveloperVocabulary, prompt templates, LLM output guard
  Diagnostics/  PerformanceMonitor spans
Sources/VoiceFlow/              (app; OS & native runtime boundaries)
  App/          AppDelegate, MenuBar, coordinator
  Hotkey/       GlobalHotkeyManager (Carbon)
  Audio/        AudioRecorder (AVAudioEngine)
  Speech/       WhisperEngine, ParakeetEngine, STTModelManager
  Processing/   LocalLLMEngine (llama.cpp)
  Insertion/    ClipboardManager, TextInserter
  Permissions/  PermissionManager
  Diagnostics/  Logger
Sources/vf-bench/               Benchmark scoring CLI
```

The spec's suggested structure is kept but split into two targets. Everything testable without hardware
goes in `VoiceFlowCore`, so the test suite runs without a microphone, GPU or permissions. The STT runtime
is replaceable (rule 15): the app depends only on the `SpeechEngine` protocol.

---

## 3. Alternatives considered

### 3.1 Language & UI

| Option | Advantages | Disadvantages | Performance | Memory | Integration | Decision |
|---|---|---|---|---|---|---|
| **Swift + AppKit** | Direct access to every API needed (menu bar, AVFoundation, Carbon hotkeys, NSPasteboard, CGEvent, AX). Calls C inference libraries directly | Some legacy APIs (Carbon) | Native | Empty shell measured at 13–14 MB footprint | Lowest | **Chosen** |
| Swift + SwiftUI `MenuBarExtra` | Declarative | Loads SwiftUI runtime for a plain menu; less control over menu behavior | Native | Higher than AppKit (not measured; not needed) | Low | Only for a future settings window, loaded lazily |
| Rust / C++ app | Performance | Every macOS API needs FFI; the inference cores are already C/C++ | Same (the heavy work is in C/C++ either way) | Similar | High | Rejected: no demonstrated benefit |
| Electron / web / Python UI | — | Forbidden by spec §8 | Poor | Hundreds of MB | — | Rejected |

### 3.2 Audio capture

| Option | Advantages | Disadvantages | Performance | Memory | Integration | Decision |
|---|---|---|---|---|---|---|
| **AVAudioEngine tap + AVAudioConverter** | Little code. Follows the default device. Built-in high-quality resampling | Engine start latency not yet measured; device-change handling needed | Real-time converter, negligible CPU | 16 kHz Float32 = 3.7 MB/min | Low | **Chosen** (re-evaluate if Phase 3 measures slow start) |
| Core Audio AUHAL | Lowest latency and overhead | Much more code (device selection, format negotiation, render callbacks) | Best | Same | High | Fallback |
| AVAudioRecorder | Simplest | Writes files; spec prefers memory buffers | — | Disk I/O | Lowest | Rejected |
| AVCaptureSession | Device selection | Built for A/V capture pipelines, heavier | — | — | Medium | Rejected |

**Sample format:** whisper.cpp and Parakeet both take 16 kHz mono Float32. Microphones deliver 48 kHz
(24 kHz on AirPods), so exactly **one** resampling step is unavoidable. It happens in the tap callback,
straight into the final buffer. No intermediate files or formats.

### 3.3 Global hotkey

| Option | Advantages | Disadvantages | Performance | Permission | Decision |
|---|---|---|---|---|---|
| **Carbon `RegisterEventHotKey`** | Press **and** release events for exactly this combo; consumes the key (no stray character) | Legacy API, but still supported and widely used | Zero cost when not pressed | **None** | **Chosen** |
| CGEventTap | Can do modifier-only hotkeys (e.g. Fn) | Sees every keystroke system-wide | Small per-key cost | Input Monitoring or Accessibility | Fallback if a modifier-only hotkey is ever wanted |
| `NSEvent.addGlobalMonitorForEvents` | Simple | Can't consume the key; every keystroke | Small per-key cost | Accessibility | Rejected |

Cancellation: Esc is registered as a second Carbon hotkey **only while RECORDING**, then unregistered, so
Esc works normally everywhere else. Duplicate or auto-repeat events are ignored unless IDLE (Phase 2 tests this).

### 3.4 Text insertion & clipboard

| Option | Advantages | Disadvantages | Works in | Permission | Decision |
|---|---|---|---|---|---|
| **Pasteboard + synthetic ⌘V** | Works nearly everywhere; fast for any length | Touches the clipboard (mitigated by snapshot/restore) | Native, Electron (VS Code, Cursor, Slack, Discord), Terminal, browsers | Accessibility (to post ⌘V) | **Chosen** |
| AX `kAXSelectedTextAttribute` | No clipboard use | Unreliable in Electron, terminals, web content | Native Cocoa text views | Accessibility | Possible later fast path, not primary |
| Unicode keystroke typing (`CGEventKeyboardSetUnicodeString`) | No clipboard use | Slow for long text; fights autocomplete/IME | Most | Accessibility | Rejected |

Clipboard algorithm (Phase 5):
1. Snapshot every `NSPasteboardItem` × every type's data (text, RTF, images, files, custom). Record `changeCount`.
2. Write the text with the `org.nspasteboard.TransientType` and `ConcealedType` markers, so clipboard managers skip it.
3. Check the frontmost app is still the one focused at key-down, then post ⌘V.
4. After a short, tuned delay, restore the snapshot **only if** `changeCount` is still ours (a user copy in between wins).
5. If ⌘V can't be posted (no permission, focus changed, secure input), leave the text on the clipboard,
   don't restore, and tell the user. Speech is never lost.

### 3.5 Local LLM runtime (Smart Mode)

| Option | Advantages | Disadvantages | Performance (measured here) | Memory | Integration | Decision |
|---|---|---|---|---|---|---|
| **llama.cpp** (in-process C API) | Mature. GGUF quantized models. Metal. No daemon. Prebuilt xcframework | Separate ggml copy from whisper.cpp's framework (duplicate Metal init, see risk below) | Qwen2.5-1.5B Q4_K_M: prompt 1033 t/s, generation 85 t/s (Metal); ~0.4 s for a short sentence | ~1.26 GB RSS while loaded | Medium | **Chosen (provisional)** |
| MLX (mlx-swift) | Apple-optimized; often fast generation on Apple Silicon | Can't build from source without Xcode (Metal toolchain). Prebuilt `Cmlx.xcframework` is 202 MB zipped | Not measured yet (Phase 7, via mlx-lm CLI for a like-for-like comparison) | Unknown | High here | Re-evaluate in Phase 7 |
| Ollama | Easy model management | Separate always-on daemon + localhost HTTP (spec §8, §10: no server, no IPC) | Same llama.cpp core plus IPC overhead | Daemon idle RAM | Low | **Rejected** |
| Apple Foundation Models (on-device) | Zero model files; OS-managed | Model and prompt behavior not controllable or benchmarkable to the same degree; availability depends on Apple Intelligence settings | Not measured | OS-managed | Low | Worth one test in Phase 7 |

**Risk:** whisper.xcframework and llama.xcframework each embed ggml. Separate dynamic frameworks keep
symbols apart (two-level namespace), but may double Metal pipeline setup. Phase 7 measures both frameworks
side by side vs using llama.cpp's ggml build for both.

**LLM guardrails (spec §5, §12):** few-shot "transform only" prompts at temperature 0. Output guard: reject
output that adds code fences, answers, or is much longer or shorter than the input, and fall back to raw STT.
Protected tokens: identifiers, commands, paths and URLs from the STT output must survive verbatim. The LLM
never "corrects" a technical term that isn't already in the transcript. Phase 0 evidence of the need: a
zero-shot prompt turned a dictated sentence into a TypeScript code block (see PERFORMANCE.md).

### 3.6 Model storage & loading

| Option | Advantages | Disadvantages | Decision |
|---|---|---|---|
| **Models in `~/Library/Application Support/VoiceFlow/models/`** | Small app bundle; models swappable; survive app updates | Needs a setup step | **Chosen**: explicit `scripts/fetch-models.sh` (later an explicit "Download model" menu action, never automatic) |
| Models inside the `.app` | Self-contained | 0.5–1.6 GB bundle; re-copied on every build | Rejected |

Model status detection (STTModelManager): **missing** (no file), **corrupted** (size/SHA-256 mismatch with
the recorded manifest), **incompatible** (runtime refuses to load it, or the header/ftype is unsupported),
**installed**. The setup script already verifies SHA-256 against Hugging Face metadata. The app records
the hash at install and re-verifies lazily, not on every launch (hashing 1.5 GB costs ~1 s).

**Cold vs warm strategy:** decided in Phase 6 from measurements (spec §22). The Phase 0 harness already
records load time, first-run time and footprint after load per model (PERFORMANCE.md). Current hypothesis:
load on first use, keep warm for an idle window (e.g. 10 min), then unload. Validate against measured
load latency vs resident memory.

---

## 4. STT decision

Data: ACCURACY.md §5 and PERFORMANCE.md §3. Measured 2026-09-16/17 on this machine.

### 4.1 Models evaluated and why

| Candidate | Why considered | Outcome (synthetic set) |
|---|---|---|
| Whisper small.en (whisper.cpp) | Fastest plausible English Whisper; baseline | 2.8% WER, 90.6% terms, 0.27 s → **finalist** (must hold up on real speech) |
| Whisper medium.en q8_0 | English-only accuracy tier | 2.8% WER, 91.5% terms, 0.84 s → **finalist** |
| Whisper large-v3-turbo f16 | Near-large-v3 accuracy with a fast decoder; multilingual | 2.2% WER, 91.9% terms, 1.39 s, 1.86 GB → replaced by q8_0 |
| **Whisper large-v3-turbo q8_0** | Same model, 8-bit | **2.3% WER, 91.5% terms, 1.16 s, 1.07 GB → provisional default** |
| large-v3-turbo q8_0 + vocabulary prompt | Developer-term biasing | +2 terms, new errors, 1.6–6× slower → keep only if the human set proves a benefit |
| Whisper distil-large-v3 | Distilled large-v3 | 6.3% WER, 76.9% terms, slower → **eliminated** |
| Parakeet TDT 0.6B v3 q8_0 (whisper.cpp) | Strong English leaderboard results, very fast | 3.7% WER, **85.0% terms**, 0.13 s → finalist as speed reference; weaker developer vocabulary |
| Apple SpeechTranscriber (en-US / en-IN / + contextual strings) | Zero dependency, OS-managed | 11.1% WER, **58.5% terms**; contextual strings no effect → **eliminated** |
| tiny.en, base.en | — | Not benchmarked: below the accuracy tier (developer-term failures in the v1 exploration) |
| MLX Whisper, WhisperKit | Other runtimes for the same Whisper weights | Not benchmarked: no expected accuracy gain; Python / heavier dependency chain. Reconsider only for speed (Phase 6) |

### 4.2 Runtime decision: whisper.cpp
- Runs the accuracy leaders in-process with Metal (no daemon, no IPC), through one 8.5 MB prebuilt framework
  that also runs Parakeet. The model can change without a new dependency.
- Metal is required: CPU was 15–30× slower (PERFORMANCE.md §3.2).
- Integration constraints found: free contexts before exit (ggml Metal teardown assert); one-time runtime
  shader compile per new binary.

### 4.3 Model decision

**Synthetic set (2026-09-16/17):** couldn't separate the Whisper finalists (shared TTS mispronunciations).
Eliminated Apple SpeechTranscriber and distil-large-v3.

**Owner's voice, MacBook mic (2026-09-17), the decision set:**

| Config | WER | Terms | Mean / p95 latency | Loaded | Status |
|---|---|---|---|---|---|
| **medium.en q8_0 + vocabulary prompt** | 2.1% | 97.4% | 0.84 / 1.32 s | ~1.13 GB | **Provisional default** |
| large-v3-turbo q8_0 + vocabulary prompt | 2.0% | 97.4% | 1.42 / 1.60 s | ~1.05 GB | Alternate (one hallucinated insertion observed) |
| any model *without* the prompt | 2.1–4.1% | ≤ 93.6% | — | — | Fail the ≥95% term threshold |
| small.en ± prompt, Parakeet, distil, Apple | ≥ 4.0% | ≤ 93.6% | — | — | Eliminated |

**Why medium.en + prompt:** tied with large-v3-turbo + prompt on accuracy (76/78 terms), no unspoken
insertion observed, ~41% lower latency. English-only: Hinglish would require large-v3-turbo.

**Consequence for the design:** the developer vocabulary prompt (`initial_prompt`) is part of the STT
configuration, not an optional extra. It's decode-time biasing toward terms actually present in the audio,
not post-hoc correction, so it's consistent with rule 8. It needs guarding: the in-app engine checks for
repeated or inserted n-grams, and Phase 4 re-measures the insertion rate on more recordings.

**Final decision at the Phase 4 gate**, after the open items in ACCURACY.md §5.6: reviewed reading variations,
the "cube control" scoring policy, threshold approval (the per-category criterion is noisy at 8–10 terms), and
more real recordings.

### 4.4 Performance measurements collected (per configuration)
Model size, load time, first-run time, per-clip warm latency (mean/p95/max), real-time factor, process CPU
time, per-process Metal GPU time, footprint after load, peak footprint; CPU vs Metal on a sample. Human-set
runs add per-microphone results. In-app cold vs warm and end-to-end latency follow in Phases 4–6.

---

## 5. Privacy & security

| Topic | Design |
|---|---|
| Microphone | Active only between hotkey press and release (macOS orange indicator confirms). No continuous listening |
| Accessibility | Needed only to post ⌘V. The app explains why and links to System Settings. Without it, text is left on the clipboard with a notice |
| Input Monitoring | Not needed (Carbon hotkeys) |
| Audio | In memory only; released after transcription. No temp files. Benchmark clips are a separate, explicit developer workflow, gitignored |
| Transcripts | Never persisted or logged. Logs record timings, sizes and states only |
| Clipboard | Snapshot kept in memory for well under a second; restored unless the user copied something meanwhile. Transient/concealed markers |
| Network | **None at runtime.** No telemetry, analytics, crash upload or update checks. Only the explicit setup scripts download (HTTPS, SHA-256 verified). Verified with networking disabled in Phase 13 |
| Models | Data files parsed by native code: only from trusted sources, integrity-checked |
| Commands | Nothing spoken is ever executed |

## 6. Dependencies

| Dependency | Version | Why | Footprint |
|---|---|---|---|
| Apple frameworks (AppKit, Foundation, AVFoundation, Carbon.HIToolbox, CoreGraphics, ApplicationServices, Speech*) | OS | UI, audio, hotkey, events, pasteboard. *Speech only if SpeechTranscriber is chosen | 0 |
| **whisper.cpp** `whisper.xcframework` (includes ggml, Parakeet) | b5130 (v1.9.4), SHA-256 `033a43b0…6f231a` | Local STT on Metal, C API, no daemon; runs both Whisper and Parakeet | 8.5 MB universal (≈4 MB arm64-only) |
| **llama.cpp** | b11005 (v0.4.1) candidate | Smart Mode LLM, in-process | TBD Phase 7 |

No Swift package dependencies. Build/dev only: Swift toolchain, `codesign`, `curl`, `shasum`, `unzip`, `say`, `python3` (scripts).
Rejected: Ollama (daemon), MLX-Swift (no Xcode; weight), WhisperKit (CoreML model pipeline plus
swift-transformers chain; kept as a fallback candidate if whisper.cpp fails accuracy), Python ML stacks,
hotkey Swift packages (~50 lines of Carbon code do the job).
