# VoiceFlow — Progress Tracker

> **Single source of truth for where the project stands.** Read first in every session. Update at the
> end of every phase, and whenever work pauses mid-phase. Requirements: [`SPEC.md`](SPEC.md) (v2).

## Status at a glance

| Phase | Name | Status |
|---|---|---|
| 0 | Machine & architecture discovery | ✅ Complete (2026-09-17; STT model final at Phase 4 gate) |
| 1 | Native macOS shell | ✅ Complete (2026-09-17, owner verified menu) |
| 2 | Global hotkey | ✅ Complete (2026-09-17, owner tested) |
| 3 | Audio recording | ✅ Complete (2026-09-17, owner tested incl. AirPods) |
| 4 | STT integration (+ accuracy gate) | ✅ Gate passed 2026-09-17 (medium.en q8_0 + vocab); owner live test pending |
| 5 | Text insertion (first usable product) | 🟡 Working in VS Code/WhatsApp; long-dictation fix awaiting owner re-test |
| 6 | Fast path optimization | ⬜ |
| 7 | Local LLM (Smart Mode) | ⬜ |
| 8 | Text modes | ⬜ |
| 9 | Developer intelligence | ⬜ |
| 10 | Application awareness | ⬜ |
| 11 | Final performance optimization | ⬜ |
| 12 | Packaging | ⬜ |
| 13 | Final audit | ⬜ |

Legend: ✅ complete · 🟡 in progress / awaiting approval · ⏭️ next · ⬜ not started · ⚠️ blocked

**Per-phase routine (spec §25):** inspect → explain → implement only that phase → build → test →
benchmark → fix → review → CPU/RAM check → docs + this file → show changes → commit → **stop for approval**.

---

## History

- **2026-09-16, spec v1:** first Phase 0 pass (commit `d8e800f`): SwiftPM shell, whisper.cpp/llama.cpp
  exploration, latency-first docs.
- **2026-09-16, spec v2 (current):** owner replaced the spec. **Accuracy first.** Phase 0 redone:
  STT candidates re-evaluated at the accuracy tier, developer-speech corpus + scorer + harness built,
  docs consolidated to ARCHITECTURE / ACCURACY / PERFORMANCE / DEVELOPMENT.

## Phase 0 — Machine & architecture discovery ✅

**Done**
- Machine and toolchain inspected → ARCHITECTURE.md §1
- Stack and alternatives for every component → ARCHITECTURE.md §2–3, privacy §5, dependencies §6
- Project restructured to standard SwiftPM layout (`Sources/VoiceFlowCore`, `Sources/VoiceFlow`, `Sources/vf-bench`)
- Accuracy benchmark scaffolding:
  - Corpus `benchmarks/corpus/developer-speech.json`: 54 phrases (normal 6, technical 12, identifiers 8,
    commands 8, files 7, architecture 5, long natural 4, Hinglish 4)
  - Scorer in `VoiceFlowCore/Speech/Accuracy` (WER vs spoken words, term recognition, exact spelling,
    formatting WER) with 14 unit tests
  - `scripts/bench/stt_engines.swift`: whisper.cpp / Parakeet / Apple SpeechTranscriber harness
    (latency, RTF, CPU time, per-process GPU time, memory footprint)
  - `scripts/bench/make-audio.sh` (3 TTS voices), `scripts/bench/record.sh` (owner's voice), `scripts/bench/stt.sh` (driver + report)
  - `scripts/fetch-models.sh` verifies SHA-256 against Hugging Face metadata
- Synthetic-voice benchmark: 10 Metal/OS configurations × 150 clips + CPU-vs-Metal sample → ACCURACY.md §5, PERFORMANCE.md §3
  - Eliminated: Apple SpeechTranscriber (58.5% term recognition), distil-large-v3 (76.9%), large-v3-turbo f16 (q8_0 equal accuracy, less memory), CPU backend (15–30× slower)
  - Provisional default: **Whisper large-v3-turbo q8_0** (2.3% WER, 91.5% terms, 1.16 s/clip, ~1.05 GB loaded)
  - Human-set finalists: large-v3-turbo q8_0, medium.en q8_0, small.en, Parakeet v3 (speed reference)
- Validated: clean build, 14 tests pass, app launches (14 MB footprint, 0.0% CPU) and quits; bundle 196 KB
  (executable grew 60 → 188 KB because it links VoiceFlowCore's scorer)

- **Owner-voice benchmark (MacBook mic, 50 clips), 2026-09-17** → ACCURACY.md §5.4–5.6:
  - Without the developer vocabulary prompt, **no model meets ≥95% term recognition** (best 93.6%)
  - After owner decisions (kubectl pronunciation, Helm/git confirmed): **large-v3-turbo q8_0 + vocab** 1.8% WER, 98.7% terms,
    the only config meeting every criterion → **provisional default**; medium.en q8_0 + vocab 97.4% (files 8/9) → alternate
  - Eliminated on real speech: small.en (±vocab), Parakeet, distil-large-v3, Apple SpeechTranscriber
  - Scorer fix: contractions / "ok" treated as equivalent (was the whole 3.2% normal-English WER); 15 tests
  - `vf-bench`: per-category term table; `--overrides-dir` for reviewed "what was actually said" corrections
- Owner approved moving forward (2026-09-17)

**Leftovers carried forward**
- Phase 4 gate closed (D1–D5 resolved). Optional confirmation: second scripted take. Hinglish not supported by the chosen
  English-only model (would need large-v3-turbo).
- Phase 9 targets from the gate: "nginx.com" for nginx.conf (medium.en), "help" for Helm (all models).
- Hinglish: needs human recordings plus a multilingual model run (large-v3-turbo with language auto/hi).
- MLX and Apple Foundation Models LLM comparison: Phase 7.
- ✅ "VoiceFlow Dev" signing identity created by owner (2026-09-17); build script fixed to use untrusted self-signed identities
  by hash and to drop the hardened runtime. Designated requirement is certificate-leaf based (stable across rebuilds).
- Phase 3: `AVAudioNode.installTap(onBus:bufferSize:format:block:)` is **deprecated in macOS 27**. Use
  `installAudioTap(onBus:bufferSize:format:tapProvider:) throws` behind `#available(macOS 27, *)` (the app
  targets macOS 14+). `scripts/bench/record.swift` still uses the old API (dev tool; warning only).
- Phase 6: Whisper latency is ~fixed per clip (30 s encoder window). Evaluate `audio_ctx` reduction only with
  an unchanged human-set accuracy. Handle the one-time Metal shader compile per new binary.
- Vocabulary prompt: decisive on real speech (+4 terms, +11–14% latency) but produced one unspoken insertion with large-v3-turbo. Keep, guard, and re-measure.

## Phase 1 — Native macOS shell ✅
- [x] Menu bar item (template mic icon) + menu built on demand: version, "● Ready", Mode (Fast ✓ / Smart
      disabled), Open Settings File… (⌘,), Quit (⌘Q) — `Sources/VoiceFlow/MenuBar/MenuBarController.swift`
- [x] Lifecycle: accessory app, launch time logged from kernel process start, terminate logged
- [x] Logging: `Log` categories (lifecycle, settings) under `local.voiceflow.VoiceFlow`; no content
- [x] Settings foundation (`VoiceFlowCore/Settings`): `Settings` (processingMode, hotkey ⌥Space,
      maxRecordingSeconds) with per-key default fallback; `SettingsStore` JSON with atomic writes; invalid file
      preserved as `settings.invalid.json` → defaults. 6 new tests (21 total)
- [x] `scripts/measure-idle.sh`: launch, idle CPU / wakeups / GPU / footprint, quit → PERFORMANCE.md §2.1
- [x] Verified: build, tests, launch ×5, quit ×3 (~225 ms), corrupt-settings path end to end (logged, preserved, app keeps running)
- [x] Owner verified the menu (items, Fast ✓, Open Settings File…, Quit), 2026-09-17. Note: `scripts/measure-idle.sh`
      quits the app when done, so relaunch with `open build/VoiceFlow.app` afterwards
- Moved to Phase 2: `PipelineState` state machine (spec v2 pairs state transitions with the hotkey phase)

Measured: launch 85–110 ms (653 ms on the first run of a new build), idle CPU 0.00 s over 60 s, 2–5 wakeups
per 30–60 s, GPU 0, footprint 13 MB.

## Phase 2 — Global hotkey ✅
- [x] `PipelineStateMachine` (VoiceFlowCore/State): explicit transition table, cancel, duplicate/stray-event
      rejection, Smart-Mode fallback to the transcript, error recovery; exhaustive state×event test (30 tests total)
- [x] `GlobalHotkeyManager` (Carbon `RegisterEventHotKey`, press + release, dispatch-latency measurement)
- [x] Esc and ⌥Esc cancel registered only while recording
- [x] `DictationCoordinator`: hotkey → state machine → effects. Phase 2 stub: release → transcribing →
      `transcriptionEmpty` → idle (no audio/STT yet)
- [x] Menu bar: icon per state (red mic while recording), status text, Dismiss on error; registration
      failure ("already used by another app") surfaces as an error state
- [x] Build, tests, idle unchanged (0.00 s CPU / 30 s, GPU 0, 13 MB); ⌥Space registered OK
- [x] Owner test (2026-09-17): hold/release, quick tap, Esc cancel, long holds (14 s), VS Code/browser/Notes focused,
      no stray characters; release-⌥-first keeps recording until Space is up (accepted, no leak)
- [x] Bug found and fixed: hotkey events are held by macOS while VoiceFlow's own menu is open, then replayed together
      (a 1 ms "recording"). Presses > 500 ms late are now ignored as stale (owner verified)
- [x] Bug found and fixed: `contentTintColor` is ignored for status items → red palette symbol while recording (owner verified)
- [x] Measured: dispatch latency median 0.13 ms, p95 0.31 ms, max 0.69 ms (n=26 presses); idle unchanged
      (0.00 s CPU, 1 wakeup / 30 s, GPU 0, 13 MB) → PERFORMANCE.md §2.2–2.3

## Phase 3 — Audio recording ✅
- [x] `AudioRecorder`: AVAudioEngine tap (macOS 27 `installAudioTap`, `installTap` fallback) → AVAudioConverter →
      16 kHz mono Float32 in memory; lock-protected sink; sample cap = `maxRecordingSeconds` (limit → keep audio);
      input-device change mid-recording → stop with the audio so far and rebuild the engine; engine reused (measured)
- [x] `RecordingGate` (Core, 6 tests): tooShort < 0.3 s; silent < 0.15 s above −45 dBFS. Thresholds calibrated on owner clips
- [x] Microphone permission: first-use prompt → error "allow, then try again"; denied → error with "Open Microphone
      Settings…" (`PipelineFailure.recovery`)
- [x] Coordinator: begin/finish/cancel recording, per-recording metrics log (press → running, first buffer, leading
      silence, peak, speech, verdict, CPU, footprint); Phase 3 stub still ends at transcribing → idle
- [x] Opt-in `saveRecordingsForDebugging` (off by default) + measurement mode (`--measure-recording`, `scripts/measure-recording.sh`)
- [x] Verified: owner granted mic permission and recorded speech (kept) and a tap (tooShort); 12 silent runs → silent;
      max duration 3 s → stopped at 3.00 s; speaker playback → in-app WAV → Whisper transcript correct; owner settings
      backed up/restored around tests; 36 tests pass; no build warnings
- [x] Measured → PERFORMANCE.md §4: press → first audio 173–184 ms warm (246 ms cold); ~0.7 % CPU while recording;
      +2–3 MB during recording; idle after mic use 5–8 wakeups/30 s, ~0.01 s CPU/30 s
- [x] Owner checks (2026-09-17): Esc during recording → discarded, orange mic indicator off immediately; indicator only
      while holding; AirPods recording worked (15 s, kept)
- Known limitation → Phase 6: speech right after the press can be clipped. Built-in mic ~0.18 s; **AirPods ~0.53 s**
  (342 ms of leading silence during the Bluetooth profile switch). No pre-roll by design

## Phase 4 — STT integration (accuracy gate) ✅
- [x] Core: `SpeechEngine` protocol, `TranscriptionResult`, `STTModel` catalog (large-v3-turbo q8_0 default, medium.en q8_0
      alternate; size + SHA-256), `STTModelStatus`, `ModelVerificationRecord`, `TranscriptGuard` (removes non-speech tags,
      collapses decoder loops, drops stock silence phrases; never adds/replaces words), retry-transcription transition,
      STT settings (`sttModelID`, `useVocabularyPrompt`, `sttUnloadAfterSeconds`). 48 tests
- [x] App: `whisper.xcframework` binary target (bundle thinned to arm64: app 4.8 MB), `WhisperEngine` (lock-serialized context,
      same inference params as the benchmark), `STTModelManager` (quick size check at launch, SHA-256 once per file state,
      bundled vocabulary prompt), coordinator (load starts at recording start, transcribe on release, guard, retry on failure
      with audio kept, one-shot idle unload, free on quit), menu (model status + install command, Last transcript,
      Copy Last Transcript, Retry Transcription), `--transcribe-benchmark` mode
- [x] Verified: in-app STT == benchmark on owner's 50 clips (50/50 identical; WER 1.8%, terms 98.7%); live pipeline with
      speaker playback (3 dictations, release → text 1114–1146 ms); idle unload; missing model → clear error + retry, no crash
- [x] Bugs found and fixed: SHA-256 autorelease buildup (+850 MB); stale failed-preparation reuse; measurement-mode
      double completion from nested transitions; **ggml Metal residency polling thread (~100 wakeups/s forever) → disabled**
      (A/B: no latency cost)
- [x] Measured → PERFORMANCE.md §3.4
- [ ] **Owner live test:** dictate a few developer sentences; open the menu → Last transcript / Copy Last Transcript; judge accuracy
- [x] **Accuracy gate passed (ACCURACY.md §5.6–5.8):** owner reviewed references (D1), approved the threshold incl. invented
      phrases ≤ 1/100 (D3), and chose not to save everyday dictations (D4). Scorer gained an invented-phrase metric (3 tests).
      Result: medium.en q8_0 + vocab passes (WER 1.1%, terms 97.4%, 0 invented); large-v3-turbo + vocab fails (2.0/100,
      "run dev"). **Default switched to medium.en**; in-app == benchmark 50/50; live release → text 914–1015 ms
- [ ] Recommended confirmation (not blocking): second scripted take (`scripts/bench/record.sh macbook-mic-take2` or AirPods) → rerun gate at n = 100
- Known → Phase 6: release → text ~1.1 s (fixed 30 s encoder window); ~170 MB remains allocated in whisper.cpp after
  unload (baseline 14 MB) → evaluate a helper process or upstream fix; cold vs warm unload timing

## Phase 5 — Text insertion 🟡
- [x] Core `InsertionPolicy` (paste vs leave on clipboard: Accessibility, focus change, no focused app; restore only if the
      clipboard is unchanged since write) + 7 tests
- [x] `ClipboardManager`: full snapshot (all items × all types), transcript written with nspasteboard.org transient/concealed
      markers, exact restore. 3 tests on private pasteboards (new `VoiceFlowTests` target)
- [x] `TextInserter`: policy → snapshot → write → ⌘V (`CGEvent`, Command-only flags, so a held ⌥ doesn't leak) → restore
      after 250 ms if unchanged; metrics (snapshot size/time, write, event, release → pasted)
- [x] Coordinator: remembers the frontmost app at key press; leave-on-clipboard outcomes → error with message (+ Open
      Accessibility Settings); measurement mode never pastes
- [x] Menu: Accessibility status and "Open Accessibility Settings…", status "Pasting…"
- [x] Owner tests so far (2026-09-17): Accessibility granted; pasted into VS Code and WhatsApp with the clipboard restored every time;
      the not-granted path copied instead; switching apps during transcription → copied, not pasted → PERFORMANCE.md §4.4
- [x] **Bug found by owner: long dictations dropped speech and invented repeated text** (89.7 s, 54.6 s speech → 69 words).
      Built a long-form benchmark from owner recordings (`make-longform.py`) that reproduces the dropped speech (WER 22.7%).
      Fix: `SpeechSegmenter` (Core, 8 tests) → WER 0.7%, terms 97.4%, no regression on the 50-clip set (ACCURACY.md §5.9)
- [x] Owner request: paste into the app focused when the transcript is ready (start dictating in Terminal, switch to a browser field,
      the text lands there). `InsertionPolicy.PasteTarget` (`currentApp` default, `dictationApp` optional) + tests; setting `pasteInto`
- [ ] **Owner re-test:** a long dictation (60 s+ with natural pauses); switch apps while dictating → pasted into the new field;
      Terminal, a browser field, Slack/Discord or Notes; clipboard preserved with an image on the clipboard
- Phase 6 notes: footprint with model loaded grew 1,185 → ~1,500 MB during the owner session (investigate); restore delay
  250 ms unproblematic so far

## Phases 6–13
Per SPEC.md. Notes so far:
- **5:** clipboard algorithm in ARCHITECTURE.md §3.4. Never lose speech on paste failure.
- **6:** cold vs warm decision from load time and footprint data (PERFORMANCE.md). First-ever Metal
  shader compile (~15 s per new binary) needs handling.
- **7:** Qwen2.5-1.5B zero-shot prompt produced a code block (spec violation); few-shot worked. Output
  guard and fallback to raw STT are mandatory. Compare llama.cpp vs MLX vs Apple Foundation Models.

---

## Decision log

| Date | Decision | Why | Where |
|---|---|---|---|
| 2026-09-16 | Swift 6 + AppKit menu-bar app, SwiftPM + script-built .app | Native APIs, minimal footprint; no Xcode (owner choice) | ARCHITECTURE §3.1 |
| 2026-09-16 | whisper.cpp framework as STT runtime (runs Whisper and Parakeet) | In-process, Metal, no daemon, prebuilt, replaceable behind a protocol | ARCHITECTURE §4 |
| 2026-09-16 | STT model chosen on the owner's recordings, never on synthetic audio alone | TTS audio isn't representative of real accents/pace (spec §3) | ACCURACY §2 |
| 2026-09-17 | Provisional STT default: Whisper large-v3-turbo q8_0 on Metal; Apple Speech, distil-large-v3 and CPU backend eliminated | Synthetic benchmark: lowest WER; Apple 58.5% terms; CPU 15–30× slower | ARCHITECTURE §4 |
| 2026-09-17 | Provisional STT: medium.en q8_0 + vocab, superseded the same day ↓ | Tied at 97.4% before owner scoring decisions | — |
| 2026-09-17 | Owner: "cube control" = kubectl pronunciation; "Helm" and "git" were said | Listening review | ACCURACY §5.5 |
| 2026-09-17 | Provisional STT: large-v3-turbo q8_0 + prompt, superseded the same day ↓ | Before the invented-phrase criterion was measured | — |
| 2026-09-17 | Owner approved the accuracy threshold (incl. ≤ 1 invented phrase / 100 clips); reviewed references; no everyday dictation saving | Owner decisions D1, D3, D4 | ACCURACY §3, §5.6 |
| 2026-09-17 | **STT: Whisper medium.en q8_0 + developer vocabulary prompt** (default); large-v3-turbo + prompt alternate | Only configuration passing the approved gate (0 invented phrases); ~40% faster | ARCHITECTURE §4.3, ACCURACY §5.8 |
| 2026-09-17 | Disable ggml Metal residency sets (`GGML_METAL_NO_RESIDENCY`) | Otherwise a 5 ms polling thread runs for the process lifetime; A/B shows no latency cost | PERFORMANCE §3.4 |
| 2026-09-17 | Load STT model at recording start; idle unload via one-shot timer (300 s provisional) | Model ready at release; memory returned when idle (except ~170 MB whisper.cpp residue) | ARCHITECTURE §3.6 |
| 2026-09-17 | Paste via clipboard snapshot → ⌘V → restore after 250 ms; paste only into the app focused at key press | Owner-tested in VS Code/WhatsApp; never loses text | ARCHITECTURE §3.4 |
| 2026-09-17 | Paste into the app focused when the transcript is ready (switch apps while dictating); `pasteInto: dictationApp` keeps the old behavior | Owner request (Wispr Flow-style continuity); last transcript stays in the menu | ARCHITECTURE §3.4 |
| 2026-09-17 | Segment dictations > 29 s at pauses into independent chunks | Owner's long dictation lost speech and invented a loop; long-form WER 22.7% → 0.7%, no short-clip regression | ACCURACY §5.9 |
| 2026-09-16 | Carbon RegisterEventHotKey; Esc cancel registered only while recording | Press+release, no permission, zero idle cost | ARCHITECTURE §3.3 |
| 2026-09-16 | Clipboard + ⌘V with full snapshot/restore; never lose speech | Works in Electron/terminals/browsers | ARCHITECTURE §3.4 |
| 2026-09-16 | llama.cpp in-process (provisional); Ollama rejected | No daemon/IPC; MLX re-evaluated in Phase 7 | ARCHITECTURE §3.5 |

## Session handoff notes
_Overwrite at the end of every session._

- **Last session (2026-09-17):** Phases 0–4 complete (gate passed with medium.en q8_0 + vocab). Owner live test of dictation pending.
- **Models on this machine** (`~/Library/Application Support/VoiceFlow/models/`): whisper tiny.en, base.en,
  small.en, medium.en-q8_0, large-v3-turbo, large-v3-turbo-q8_0, distil-large-v3; parakeet tdt-0.6b-v3-q8_0;
  llm qwen2.5-1.5b-instruct-q4_k_m.
- **Owner recordings:** `benchmarks-output/audio/human/macbook-mic/` (50 clips + `spoken-overrides.json`, gitignored). Results cached in
  `benchmarks-output/results/human/`. Rerunning `scripts/bench/stt.sh human` re-scores instantly.
- **Next action:** owner re-tests long dictation + remaining apps → close Phase 5 → approval for Phase 6. Optional: second scripted take.
