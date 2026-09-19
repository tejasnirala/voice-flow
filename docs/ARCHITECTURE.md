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
| **STT runtime** | **whisper.cpp** (prebuilt `whisper.xcframework`) behind a `SpeechEngine` protocol: **encoder on the Neural Engine via Core ML** (optional `…-encoder.mlmodelc` beside the model; falls back to Metal), decoder on Metal | Decided by measurement (§4, PERFORMANCE.md §3.6) |
| **STT model** | **Whisper medium.en q8_0 + developer vocabulary prompt** (alternate: large-v3-turbo q8_0 + prompt), §4.3 | Decided at Phase 4 gate (2026-09-17); second take to confirm |
| **Text processing** | **Rule-based cleanup** (always, `cleanupTranscripts`); **Smart Mode** (optional): Apple on-device foundation model (FoundationModels) + deterministic `RewriteGuard`, falling back to the cleaned transcript | Decided by measurement (ACCURACY.md §6) |
| **LLM model** | Apple's system model (no model files); llama.cpp models evaluated and not adopted | Decided (Phase 7) |
| **Text insertion** | Full pasteboard snapshot → set text (transient/concealed markers) → CGEvent ⌘V → restore if unchanged | Decided |
| **Storage** | Models: `~/Library/Application Support/VoiceFlow/models/<runtime>/`. Settings: `…/VoiceFlow/settings.json`. Logs: unified logging (`os.Logger`), no transcript content. Audio: memory only | Decided |
| **Testing** | Swift Testing unit tests on `VoiceFlowCore` (pure logic). Protocol-based fakes at hardware/model boundaries. Corpus benchmark (`vf-bench`) for STT quality | Decided |
| **Build** | SwiftPM + `scripts/build-app.sh` (assemble, embed linked frameworks, codesign) | Decided |

### Processes (Phase 6)

```
VoiceFlow.app/Contents/MacOS/VoiceFlow        menu bar, ⌥ trigger, audio, state machine, paste      ~13–18 MB, always running
VoiceFlow.app/Contents/MacOS/voiceflow-stt    whisper.cpp (Core ML encoder + Metal decoder)          ~1.2 GB, only while in use
                     ▲ stdin: prepare / transcribe(Float32) / shutdown   ▼ stdout: ready / transcription / failure
```

The app starts the helper when recording starts (launch ≈ 1–5 ms, model load ≈ 0.3 s while the user speaks) and stops
it `sttUnloadAfterSeconds` after the last dictation (default 60 s). Why a process: whisper.cpp keeps ~190 MB after
`whisper_free` and grows ~0.7 MB per load, so only process exit returns the app to its 13 MB baseline. Frames:
`VoiceFlowCore/Speech/SpeechHelperProtocol.swift` (tested). If the helper crashes or is killed, the dictation fails with
*Retry Transcription* (audio kept in the app); if the app dies, the helper sees stdin close and exits. The app never
links whisper.cpp.

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
  State/        PipelineStateMachine, PipelineFailure (with recovery hints)
  Audio/        RecordingGate (level analysis, keep/tooShort/silent), SpeechSegmenter (long-dictation chunks)
  Insertion/    InsertionPolicy (paste vs leave on clipboard, restore rule)
  Settings/     Settings model + persistence (Codable JSON)
  Speech/       SpeechEngine protocol, TranscriptionResult, STTModel catalog/status/verification record,
                STTModelManager, SpeechHelperProtocol, DeveloperVocabulary, TranscriptGuard, Accuracy/ (scorer)
  Processing/   TextProcessor, DeveloperVocabulary, prompt templates, LLM output guard
  Diagnostics/  PerformanceMonitor spans
Sources/VoiceFlow/              (app; OS & native runtime boundaries)
  App/          main, AppDelegate, coordinator
  MenuBar/      MenuBarController (status item; menu built on demand)
  Hotkey/       GlobalHotkeyManager (Carbon)
  Audio/        AudioRecorder (AVAudioEngine), DebugRecordingWriter (opt-in WAV)
  Speech/       HelperSpeechEngine (SpeechEngine over the helper process)
Sources/voiceflow-stt/          Speech helper: WhisperEngine (whisper.cpp), serve loop, --transcribe-benchmark
  Processing/   LocalLLMEngine (llama.cpp)
  Insertion/    ClipboardManager (full snapshot/restore), TextInserter (⌘V, focus check)
  Permissions/  PermissionManager (microphone; Accessibility in Phase 5)
  Diagnostics/  Log (os.Logger categories), process start time
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

**Implemented (Phase 3):** `Sources/VoiceFlow/Audio/AudioRecorder.swift`. The macOS 27 tap API
(`installAudioTap`, with `installTap` below 27), a 1024-frame tap, one `AVAudioConverter` (downmix) → 16 kHz mono
Float32 appended under an unfair lock, a hard sample cap = `maxRecordingSeconds` (limit → treated as a release,
audio kept). The stopped engine is reused (~10 ms faster, no idle difference); it's rebuilt after an input-device
change, and a change mid-recording stops with the audio captured so far. `engine.stop()` after every recording
releases the microphone. The silence/too-short gate (`VoiceFlowCore/Audio/RecordingGate.swift`) uses thresholds
calibrated on the owner's recordings (≥ 0.3 s; ≥ 0.15 s of 20 ms frames above −45 dBFS). Measured start latency
and cost: PERFORMANCE.md §4.

**Sample format:** whisper.cpp and Parakeet both take 16 kHz mono Float32. Microphones deliver 48 kHz
(24 kHz on AirPods), so exactly **one** resampling step is unavoidable. It happens in the tap callback,
straight into the final buffer. No intermediate files or formats.

### 3.3 Global hotkey

**Current trigger (owner request, 2026-09-17): ⌥ alone.** Hold ⌥ to dictate; double-tap ⌥ for hands-free dictation,
finished by the next ⌥ press; Esc cancels. A quick single tap does nothing; ⌥ used in a chord (⌥←, ⌥+letter, ⌘⌥…) cancels
silently. Gesture timing (tap < 0.3 s, second tap within 0.4 s) is pure logic in `VoiceFlowCore/Hotkey/ModifierKeyGesture`
(9 tests). Carbon hotkeys can't register a lone modifier, so `ModifierKeyMonitor` uses **listen-only event taps**: a
modifier-changes tap (always on; fires only when modifier keys change) and a key-down tap **enabled only while ⌥ is held**
to detect chords, without reading key identity. Listen-only taps can't delay or alter input. They need Input Monitoring,
which was already satisfied on the owner's machine with Accessibility granted. Without it, VoiceFlow falls back to the
⌥Space Carbon hotkey below and says so in the menu. Measured idle cost with the taps: 0.00 s CPU / 30 s, 6 wakeups, 13 MB.
The gesture only finishes or cancels a recording it started, so a tap during transcription can't discard a result.
`dictationTrigger = hotkeyCombination` selects the Carbon hotkey.

**Carbon combination hotkey (fallback / option):**

| Option | Advantages | Disadvantages | Performance | Permission | Decision |
|---|---|---|---|---|---|
| **Carbon `RegisterEventHotKey`** | Press **and** release events for exactly this combo; consumes the key (no stray character) | Legacy API, but still supported and widely used | Zero cost when not pressed | **None** | **Chosen** |
| CGEventTap | Can do modifier-only hotkeys (e.g. Fn) | Sees every keystroke system-wide | Small per-key cost | Input Monitoring or Accessibility | Fallback if a modifier-only hotkey is ever wanted |
| `NSEvent.addGlobalMonitorForEvents` | Simple | Can't consume the key; every keystroke | Small per-key cost | Accessibility | Rejected |

Cancellation: Esc and ⌥Esc are registered as Carbon hotkeys **only while RECORDING** (Carbon matches modifiers
exactly, and ⌥ is usually still held), then unregistered, so Esc works normally everywhere else.

Verified behavior (Phase 2, owner-tested 2026-09-17):
- Press and release both arrive in ~0.13 ms (PERFORMANCE.md §2.2). No keystroke leaks into the focused app,
  including during long holds.
- **Releasing ⌥ before Space keeps recording until Space is released.** The hotkey ends on the key-up of the
  hotkey's key. No characters leak meanwhile, so this is accepted (detecting modifier release would need a
  global flags monitor and likely Input Monitoring permission).
- Duplicate presses and stray releases are rejected by the state machine.
- **While VoiceFlow's own menu is open**, macOS delivers hotkey events only after it closes. Presses more
  than 500 ms late are ignored as stale rather than producing an empty recording.
- Registration failure (combination taken by another app) → error state with a message in the menu.

### 3.4 Text insertion & clipboard

| Option | Advantages | Disadvantages | Works in | Permission | Decision |
|---|---|---|---|---|---|
| **Pasteboard + synthetic ⌘V** | Works nearly everywhere; fast for any length | Touches the clipboard (mitigated by snapshot/restore) | Native, Electron (VS Code, Cursor, Slack, Discord), Terminal, browsers | Accessibility (to post ⌘V) | **Chosen** |
| AX `kAXSelectedTextAttribute` | No clipboard use | Unreliable in Electron, terminals, web content | Native Cocoa text views | Accessibility | Possible later fast path, not primary |
| Unicode keystroke typing (`CGEventKeyboardSetUnicodeString`) | No clipboard use | Slow for long text; fights autocomplete/IME | Most | Accessibility | Rejected |

**Implemented (Phase 5):** `Insertion/ClipboardManager.swift` and `TextInserter.swift`; rules in
`VoiceFlowCore/Insertion/InsertionPolicy.swift`. Verified in VS Code and WhatsApp (PERFORMANCE.md §4.4).

**Paste target (owner decision, 2026-09-17):** the transcript is pasted into the app **focused when it's ready**, so
the user can start dictating in one app, switch to another app/field while speaking, and the text lands there
(`Settings.pasteInto = currentApp`, default). `dictationApp` restores the stricter behavior (paste only into the app
focused at key press, otherwise leave on clipboard). There's no check that a text field is focused: that would need
Accessibility queries that switch Chrome/Electron into their expensive accessibility mode. The last transcript stays
in the menu (Copy Last Transcript) if a paste lands where text can't go.

Clipboard algorithm (Phase 5):
1. Snapshot every `NSPasteboardItem` × every type's data (text, RTF, images, files, custom). Record `changeCount`.
2. Write the text with the `org.nspasteboard.TransientType` and `ConcealedType` markers, so clipboard managers skip it.
3. Post ⌘V to the app focused now (or, with `pasteInto = dictationApp`, only if it's still the app focused at key-down).
4. After a short, tuned delay, restore the snapshot **only if** `changeCount` is still ours (a user copy in between wins).
5. If ⌘V can't be posted (no permission, focus changed, secure input), leave the text on the clipboard,
   don't restore, and tell the user. Speech is never lost.

### 3.5 Text processing and Smart Mode (Phase 7)

Measured on a 72-entry cleanup benchmark of real transcripts plus traps (ACCURACY.md §6).

| Option | Advantages | Disadvantages | Performance | Memory | Integration | Decision |
|---|---|---|---|---|---|---|
| **Rule-based cleanup** (`RuleBasedCleanup`) | Can't change meaning; instant; testable | Only hesitations, stutters, first-word case, end punctuation | ~0 ms | 0 | Trivial | **Always on (default)** |
| **Apple on-device foundation model** (FoundationModels) | Native API; no model files; runs in a system service; best formatting and fewest violations | Needs macOS 26+ and Apple Intelligence; model may change with OS updates; violated the contract in 5/72 | +0.79 s mean | not in VoiceFlow | Low | **Smart Mode, behind `RewriteGuard`** |
| llama.cpp + Qwen2.5 0.5–3B / Llama 3.2 1B / Gemma 3 1B | Controllable model version; fast small models | 10–37/72 violations; worse formatting; 0.6–2.3 GB models; second inference runtime | +0.18–0.68 s | 0.6–2.3 GB | Medium (another helper) | Not adopted |
| MLX | Fast on Apple Silicon | Can't build without Xcode | — | — | High here | Not evaluated |
| Ollama | Model management | Localhost daemon (spec §8) | — | Daemon RAM | Low | Rejected |

**Pipeline:** STT → `TranscriptGuard` (Whisper artifacts) → `RuleBasedCleanup` (if enabled) → *[Smart Mode]* on-device
rewrite (fresh session, greedy, bounded tokens, 5 s timeout, prewarmed at recording start) → `RewriteGuard` compares
rewrite and input (no added phrases, no dropped or replaced content words, developer terms kept, no expansion, no code) →
accept, or use the cleaned transcript. Speech is never lost: errors, timeouts and unavailability all fall back.

### 3.5.1 Text modes (Phase 8)

`TextMode` (setting `textMode`; menu **Mode**) selects the deterministic preparation, whether the on-device model runs,
the prompt and the guard policy. `processingMode: smart` is now the **Smart Rewrite** toggle for Clean and Developer.

| Mode | Deterministic step (`TextProcessingPlan.prepare`) | Model | Prompt | Guard policy |
|---|---|---|---|---|
| Raw | none | never | — | — |
| Clean (default) | `RuleBasedCleanup` | Smart Rewrite only | `clean.json` | strict |
| Developer | `RuleBasedCleanup` → `DeveloperFormatter`; re-applied after an accepted rewrite | Smart Rewrite only | `clean.json` | strict |
| Prompt | `RuleBasedCleanup` | always | `prompt.json` | content-preserving |
| Writing | `RuleBasedCleanup` | always | `writing.json` | content-preserving |

- **`DeveloperFormatter`** (rules, no model): joins spoken symbols only in unambiguous patterns ("<word> dot <known
  extension>", leading "dot env" after grammar words and verbs, "dash dash <flag>", "dash <letter>", "<a> underscore <b>",
  "<a> slash <b>"), known multi-word names (Next.js, Node.js, tsconfig.json, docker-compose.yml, PostgreSQL, GraphQL…) and
  canonical casing of whole tokens that are unambiguous product names (Redis, MongoDB, JWT, API…). Words that are also
  ordinary English or lowercase commands (express, react, docker, git, cd) are left alone. Word-level guesses (nginx.com →
  nginx.conf, "kube control" → kubectl) belong to Phase 9.
- **Guard policies** (`RewriteGuard.Policy`): *strict* = Phase 7 guard (only punctuation, case, fillers, stutters, articles
  may change). *contentPreserving* = the set of content words (normalized words minus a fixed list of grammar words and
  fillers; negations are content) must be identical in input and output, developer terms kept, no expansion, no code
  fence. Restructuring and grammar words are allowed; synonyms, answers, additions and omissions are not.
- **Lists** (after owner test): Clean, Prompt and Writing prompts make a list when the speaker explicitly enumerates.
  `ListScaffold` lets both policies accept removal of the counting words directly in front of each item (2+ items), nothing
  else. Clean/Developer keep line breaks only around list items; Developer formatting runs per line.
- Strict policy details: fillers, stutters, articles and optional "that" may be deleted; an article may become another
  article; a single added word must be a grammar word ("never", "not" are rejected).
- Content-preserving details: pronouns you/me/us/they/them are content; "so" is droppable only as a lead-in; "you know" only as
  a pair.
- The mode is captured when the transcript is ready, so a menu change during processing can't mix modes.

### 3.5.2 Developer intelligence (Phase 9)

- **`DeveloperCorrections`** (Core, rules): context-gated corrections run inside `DeveloperFormatter` after spoken symbols and
  before product casing (rule table: ACCURACY §8). Each rule names the neighbouring words it needs; nothing is replaced
  globally. Measured over-corrections on held-out text: 0.
- **Code mode** (`TextMode.code`, `CodeFormatter`): `RuleBasedCleanup(sentenceCase: false)` → spoken names → corrections with
  case cues allowed anywhere → symbol pieces (glue left/right/both, spaced operators, toggling quotes, "dash dash" flags,
  paths after shell commands keep a space) → render. Never uses the model. Intended for terminals/editors (Phase 10 can select
  it per app).
- **`UserDictionary`** (`~/Library/Application Support/VoiceFlow/dictionary.json`, menu "Open Dictionary File…"): `terms` and
  `replacements`, re-read at each recording start (a few KB, no watcher). Applied last in every mode except Raw; terms appended
  to the Whisper prompt (max 40; the helper restarts when the prompt changes) and passed to `RewriteGuard` as protected terms.
  Invalid or missing files give an empty dictionary.

| Option for corrections | Pros | Cons | Decision |
|---|---|---|---|
| Context-gated rules (chosen) | Deterministic, testable, instant, explainable | Only covers measured/known patterns | **Adopted** |
| Global replacement lexicon | Simple | Violates spec §13 (help → Helm everywhere) | Rejected |
| On-device model correction | Broad | Phase 7/8: models invent and change meaning; guard would reject corrections (word changes) | Rejected |
| Larger Whisper prompt | Helps recognition | Prompt window limited; changes accuracy, needs re-gating | Owner terms only, capped |

### 3.5.2.1 Model call (Phase 11)
- The session prewarmed at recording start (for the mode of the app in front) is the one used for the rewrite, if the final
  mode's instructions match; otherwise a new session. One session per dictation, never reused (`OnDeviceRewriter.warmSession`).
- `TextMode.usesModel(processing:wordCount:)`: Clean, Developer and Prompt skip the model for dictations of ≤ 10 words;
  Writing always rewrites. Measurements: PERFORMANCE §5.4.
- Rejected after measurement: parallel sentence chunks (slower), streaming early rejection (false rejections).

### 3.5.3 Application awareness (Phase 10)

- **Which app:** the app that receives the paste. With `pasteInto: currentApp` (default) that's the app in front when the
  transcript is ready, so switching apps mid-dictation gets the new app's mode; with `dictationApp`, the app at key press.
  The on-device model is prewarmed at recording start for the mode of the app in front then.
- **`AppModePolicy`** (Core): owner rule (`appModes[bundleID]`) → browser tab title → built-in bundle ID table → the menu's mode
  (also used when `modeByApp` is off or the app is unknown).
- **Built-in defaults:** Developer: VS Code, Cursor, Windsurf, Zed, Xcode, JetBrains, Sublime, **and terminals** (Terminal, iTerm2,
  Warp, Ghostty, kitty, Alacritty; spec says Raw/Developer: Developer keeps prose to CLI agents readable while formatting
  symbols; Code is one menu click per terminal). Clean: Slack, Discord, WhatsApp, Messages, Telegram, Teams, Mail, Outlook,
  Zoom, browsers. Prompt: ChatGPT, Claude, Gemini, Perplexity apps, and browser tabs whose focused-window title names an
  assistant (ChatGPT, Claude, Gemini, Perplexity, Copilot, DeepSeek, Grok). Writing: Notes, Notion, Obsidian, Pages, Word,
  TextEdit, Bear, Ulysses.
- **Browser tab detection:** Accessibility (`AXFocusedWindow` → `AXTitle`), already granted for pasting; 100 ms messaging timeout;
  only for browser bundle IDs; the title is matched and discarded (never stored or logged). URL reading would need Automation
  permission per browser, so it isn't used.
- **Menu:** Mode ▸ shows the resolved mode for the app in front; "Choose Mode by App" toggle; "For <App> ▸ Automatic / six modes"
  writes `appModes`. The mode list sets the default for other apps.

| Option | Pros | Cons | Decision |
|---|---|---|---|
| Bundle ID table + owner overrides (chosen) | Instant, no permission, predictable | Browser = one app | **Adopted** |
| + focused window title for browsers (chosen) | Detects AI chat tabs, no new permission | Title-based (a doc titled "Claude" matches) | **Adopted**, browsers only |
| Browser URL via AppleScript | Exact site | Automation permission per browser; slower | Rejected |
| Focused text field role/placeholder | Finer | Unreliable across Electron/web apps | Not now |

- Prompt/Writing when the on-device model is unavailable: menu items disabled with the reason; if selected anyway (settings
  file), the rule-cleaned text is pasted.

### 3.6 Model storage & loading

| Option | Advantages | Disadvantages | Decision |
|---|---|---|---|
| **Models in `~/Library/Application Support/VoiceFlow/models/`** | Small app bundle; models swappable; survive app updates | Needs a setup step | **Chosen**: explicit `scripts/fetch-models.sh` (later an explicit "Download model" menu action, never automatic) |
| Models inside the `.app` | Self-contained | 0.5–1.6 GB bundle; re-copied on every build | Rejected |

Model status detection (STTModelManager): **missing** (no file), **corrupted** (size/SHA-256 mismatch with
the recorded manifest), **incompatible** (runtime refuses to load it, or the header/ftype is unsupported),
**installed**. The setup script already verifies SHA-256 against Hugging Face metadata. The app records
the hash at install and re-verifies lazily, not on every launch (hashing 1.5 GB costs ~1 s).

**Implemented (Phase 4):** the model catalog (`STTModel`: file, size, SHA-256) lives in Core. At launch only a size
check runs (no hashing, no loading). The first time a file state is seen, SHA-256 is verified during the first
recording and remembered (`models/verified.json`). Status is shown in the menu with the install command; nothing is
downloaded at runtime. **Loading:** the model starts loading when recording starts (ready at release: 0.3–0.5 s
load), and a one-shot timer unloads it after `sttUnloadAfterSeconds` idle (default 300 s, provisional). The app frees
the model on quit. **Metal residency sets are disabled** (`GGML_METAL_NO_RESIDENCY`): with them, ggml runs a 5 ms
polling thread for the process lifetime (PERFORMANCE.md §3.4). A transcription failure keeps the audio in memory
and offers *Retry Transcription*; the last transcript is kept in memory only (menu: *Copy Last Transcript*).

**Cold vs warm strategy:** decided in Phase 6 from measurements (spec §22). The Phase 0 harness already
records load time, first-run time and footprint after load per model (PERFORMANCE.md). Current hypothesis:
load on first use, keep warm for an idle window (e.g. 10 min), then unload. Validate against measured
load latency vs resident memory.

---

### 3.7 Packaging (Phase 12)
- **Bundle:** `VoiceFlow.app` (6.9 MB): `MacOS/VoiceFlow` (menu-bar app, LSUIElement), `MacOS/voiceflow-stt` (speech helper),
  `Frameworks/whisper.framework` (arm64 only), `Resources/` (AppIcon.icns, developer-vocabulary.txt, prompts/). Signed with the
  local "VoiceFlow Dev" identity (stable permission grants); no hardened runtime or notarization (personal, not distributed).
  Version 1.0.0; build number = git commit count.
- **Data, separate from the app (spec §20):** `~/Library/Application Support/VoiceFlow/` → `models/` (never in the bundle,
  installed only by `scripts/fetch-models.sh` / `install.sh --with-models`, SHA-256 verified), `settings.json`, `dictionary.json`.
  Temporary audio stays in memory; logs in the unified log. Nothing else is written.
- **Model discovery:** the menu shows "Speech model not installed / damaged — run …" and, when the Core ML encoder is absent,
  "~25% slower without the Neural Engine encoder — run …". No runtime downloads.
- **Install:** `scripts/install.sh` (Command Line Tools only): fetch framework if missing, optional models, build, tests, `ditto`
  to `~/Applications` (or `/Applications`), launch. `scripts/uninstall.sh [--purge]`. No installer package, daemon or launch agent.
- **Open at Login:** `SMAppService.mainApp` (system login items), menu toggle.
- **Diagnostics:** menu → Copy Diagnostics / `--diagnostics`: versions, model/encoder/permission status, settings summary,
  this launch's VoiceFlow log (`OSLogStore`, current process). Logs contain no transcript text by design.
- **Failure handling verified:** speech helper killed mid-transcription → "The speech helper stopped unexpectedly" with Retry
  (audio kept), app keeps running, next dictation starts a new helper (0.66 s) and works. Earlier phases: model missing,
  microphone/accessibility/input monitoring denied, paste failure (text left on clipboard), rewrite failure (rule text used).

### 3.8 App window and floating pill (Phase 12, owner request)
Owner asked for a full app UI and a Wispr Flow–style pill. This goes beyond spec §17 ("minimal menu-bar utility, no large
settings-heavy UI"); accepted as the owner's decision, built so it costs nothing while unused.

- **Window** (`UI/MainWindowController.swift`, SwiftUI in an `NSWindow`): Home (status, last dictation in memory, setup
  checklist: microphone, Input Monitoring, Accessibility, speech model, Neural Engine encoder, on-device model), Modes, Apps
  (owner per-app rules with app icons, built-in defaults for installed apps), Dictionary (edits dictionary.json), Settings
  (trigger, paste target, longest dictation, pill on/off + reset position, model unload delay, vocabulary, Open at Login),
  About (privacy, Copy Diagnostics, data folder). Created on open and released on close; VoiceFlow joins the Dock only while
  it's open. Shown on first launch (no settings file), from the menu ("Open VoiceFlow…", ⌘O) and when the app is opened again
  from Finder/Spotlight. Launches at login stay menu-bar only.
- **Pill** (`UI/IndicatorController.swift`): borderless non-activating `NSPanel` at status-bar level on all Spaces, so it never
  takes focus from the app receiving the text. States: Starting… (until audio flows), recording with live level bars (RMS
  from the capture tap, ~20 Hz, computed only while the pill is enabled), ■ finish (hands-free or hover), ✕ cancel,
  Transcribing / Rewriting spinner, "Pasted" (0.8 s), errors (3 s). Drag anywhere; the origin is saved to settings.json
  (`indicatorPosition`) on drag end and reused; a position that's no longer on any screen falls back to bottom center of the
  screen with the pointer. Ordered out when idle.
- **State sharing:** `AppState` (`@Observable`) mirrors pipeline state, trigger info, model status and settings for the window
  and pill; the menu keeps its own copy. Both write through `SettingsStore`; AppDelegate propagates changes to the coordinator,
  menu, pill and level metering.
- **Toolchain constraint:** with Command Line Tools only, SwiftUI's `@State`/`@Entry` macros are unavailable (their plugin ships
  with Xcode). View-local state lives in small `@Observable` classes (`WindowModel`, `PillInteraction`); `@Observable` and
  `@Bindable` work.

### 3.9 Languages (Phase 14)
- **Setting:** `language` (auto default, english, german, hindi, hinglish) + `hindiScript` for Auto; `⌃⇧L` cycles (Carbon hotkey,
  no ⌥ so it can't collide with the trigger); menu, window and pill show the language.
- **Routing** (`LanguageRouting`): English → medium.en q8_0 (unchanged, the model that passed the English gate);
  Hindi/Hinglish → large-v3-turbo q8_0; German → large-v3 q5_0. Each with a vocabulary prompt in that language
  (`Resources/vocabulary-*.txt`) plus the owner's dictionary terms.
- **Per app:** `appLanguages[bundleID]` overrides `language` (e.g. WhatsApp → Hinglish); detection is skipped there.
- **Detection result:** candidates en/de/hi/ur, Urdu folded into Hindi; if the candidates hold < 0.5 probability the result
  is "unsure" and the last confident language in that app (in memory, this session) is used (ACCURACY §9.6).
- **Auto:** the helper loads the detector (turbo) and medium.en at recording start; the detector also transcribes Hindi, so only
  German needs an extra model, loaded when German is detected. Detection runs on the first ≤30 s of speech
  (`whisper_lang_auto_detect`) restricted to en/de/hi.
- **Hindi output:** always transcribed in Devanagari; `HindiTransliteration` converts to Hinglish by rules (lexicon +
  code-point romanization with schwa deletion) or, for Devanagari output, maps Devanagari-written English loanwords back to
  Latin and ends sentences with "।".
- **Text processing** follows the output language: hesitations, stutter words, question words, end punctuation; English-only
  rules (contractions, "I") stay English-only. Developer/Code symbol rules still apply to Latin words in any language.
- **Rewrites:** English and German only (Apple's model has no Hindi); German prompts get "write in German, never translate".
- **Helper protocol:** `prepare` loads a model (several at once), `transcribe` carries model/language/prompt per request, and
  `detectLanguage` returns probabilities per candidate.

| Option | Pros | Cons | Decision |
|---|---|---|---|
| One multilingual model for all languages | Simplest, least memory | English accuracy regresses (large-v3-turbo failed the English gate) | Rejected |
| Model per language (chosen) | Best accuracy per language; Hindi shares the detector | Up to 3 models loaded (3.5 GB) | **Adopted** |
| Whisper writing Hinglish directly | No conversion step | 19.6–40.7% WER, mixed scripts | Rejected |
| Devanagari + rule transliteration (chosen) | 3.5% WER, stable | Spelling conventions are ours, not personal habits | **Adopted** |
| base-model detection cascade | ~0.2 s instead of 0.48 s | Thin margins (0.01–0.47) on current data | Not yet |

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

**Owner's voice, MacBook mic (2026-09-17), the decision set**, with owner-reviewed references and the owner-approved
threshold (ACCURACY.md §3, §5.6–5.8):

| Config | WER | Terms | Invented phrases / 100 | Mean latency | Loaded | Result |
|---|---|---|---|---|---|---|
| **medium.en q8_0 + vocabulary prompt** | 1.1% | 97.4% | 0 | 0.84 s | ~1.13 GB | **Passes: chosen** |
| large-v3-turbo q8_0 + vocabulary prompt | 0.5% | 98.7% | 2.0 | 1.42 s | ~1.05 GB | Fails the invented-phrase criterion ("run dev"); alternate |
| any model without the prompt | 0.7–2.8% | ≤ 94.9% | 0 | — | — | Fails terms ≥ 95% |
| small.en ± prompt, Parakeet, distil, Apple | ≥ 2.8% | ≤ 93.6% | — | — | — | Eliminated |

**Why medium.en + prompt:** it's the only configuration passing every approved criterion. It's also ~40% faster than
large-v3-turbo. Trade-offs: English-only, and weaker on the file name nginx.conf ("nginx.com"). In-app output is
identical to the benchmark (50/50 clips). A second scripted take is recommended to confirm (n = 50; the finalists
differ by one event).

**Long dictations:** audio longer than 29 s is split by `SpeechSegmenter` (long pauses removed, ≤ 29 s chunks cut at
pauses, transcribed independently). Without it, an 89.7 s owner dictation lost most of its speech and invented a loop.
Long-form benchmark WER 22.7% → 0.7% (ACCURACY.md §5.9).

**Consequence for the design:** the developer vocabulary prompt (`initial_prompt`) is part of the STT configuration,
not an optional extra. It's decode-time biasing toward terms present in the audio, not post-hoc correction, so it's
consistent with rule 8.

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
| Audio | In memory only; released after transcription. No temp files. Exception, off by default: `saveRecordingsForDebugging` in settings.json writes WAVs to `…/VoiceFlow/debug-recordings/` for quality checks and benchmarks (logged when used). Benchmark clips are a separate, explicit developer workflow, gitignored |
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
