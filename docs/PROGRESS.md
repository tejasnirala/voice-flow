# VoiceFlow — Progress Tracker

> **Single source of truth for where the project stands.** Read first in every session. Update at the
> end of every phase, and whenever work pauses mid-phase. Requirements: [`SPEC.md`](SPEC.md) (v2).

## Status at a glance

| Phase | Name | Status |
|---|---|---|
| 0 | Machine & architecture discovery | ✅ Complete (2026-09-17; STT model final at Phase 4 gate) |
| 1 | Native macOS shell | ✅ Complete (2026-09-17, owner verified menu) |
| 2 | Global hotkey | ✅ Complete (2026-09-17, owner tested) |
| 3 | Audio recording | ⏭️ Next (after approval) |
| 4 | STT integration (+ accuracy gate) | ⬜ |
| 5 | Text insertion (first usable product) | ⬜ |
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
- **Phase 4 gate (STT model final), ACCURACY.md §5.6:** D1 six clips still to review (technical-03, technical-04,
  architecture-04, architecture-05, natural-01, natural-02); D2 ✅ "cube control" accepted; D3 threshold approval,
  including a proposed inserted-phrase criterion; D4 more recordings to measure the insertion rate of large-v3-turbo + vocab;
  D5 ✅ Helm confirmed (genuine error in all models). Add an inserted/repeated n-gram guard to the engine.
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

## Phase 3 — Audio recording
AVAudioEngine tap → one resample to 16 kHz mono Float32 in memory; max duration; cancellation; silence
and too-short detection; permission errors. Measure start latency per input device (built-in, AirPods,
iPhone), memory, CPU.

## Phase 4 — STT integration (accuracy gate)
`SpeechEngine` protocol → whisper.cpp engine (and Parakeet if still a finalist); STTModelManager
(installed/missing/corrupted/incompatible); in-app instrumentation. Run the human corpus benchmark.
**Don't pass this phase until the chosen model meets the approved threshold.**

## Phases 5–13
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
| 2026-09-17 | **Provisional STT: large-v3-turbo q8_0 + developer vocabulary prompt**; medium.en q8_0 + prompt alternate | Only config meeting every proposed criterion (98.7% terms); insertion risk tracked (D3/D4) | ARCHITECTURE §4.3, ACCURACY §5.6 |
| 2026-09-16 | Carbon RegisterEventHotKey; Esc cancel registered only while recording | Press+release, no permission, zero idle cost | ARCHITECTURE §3.3 |
| 2026-09-16 | Clipboard + ⌘V with full snapshot/restore; never lose speech | Works in Electron/terminals/browsers | ARCHITECTURE §3.4 |
| 2026-09-16 | llama.cpp in-process (provisional); Ollama rejected | No daemon/IPC; MLX re-evaluated in Phase 7 | ARCHITECTURE §3.5 |

## Session handoff notes
_Overwrite at the end of every session._

- **Last session (2026-09-17):** Phases 0–2 complete; awaiting owner approval for Phase 3 (audio recording).
- **Models on this machine** (`~/Library/Application Support/VoiceFlow/models/`): whisper tiny.en, base.en,
  small.en, medium.en-q8_0, large-v3-turbo, large-v3-turbo-q8_0, distil-large-v3; parakeet tdt-0.6b-v3-q8_0;
  llm qwen2.5-1.5b-instruct-q4_k_m.
- **Owner recordings:** `benchmarks-output/audio/human/macbook-mic/` (50 clips, gitignored). Results cached in
  `benchmarks-output/results/human/`. Rerunning `scripts/bench/stt.sh human` re-scores instantly.
- **Next action:** owner approval → Phase 3. Before Phase 3: create the "VoiceFlow Dev" signing identity (microphone permission). Phase 4 gate items D1, D3, D4 are waiting on the owner.
