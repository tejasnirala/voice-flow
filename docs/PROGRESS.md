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
| 5 | Text insertion (first usable product) | ✅ Complete (2026-09-17, owner tested) |
| 6 | Fast path optimization | ✅ Complete (2026-09-17, owner verified in real use) |
| 7 | Local LLM (Smart Mode) | ✅ Complete (2026-09-17) |
| 8 | Text modes | ✅ Complete (2026-09-17, owner approved) |
| 9 | Developer intelligence | ✅ Complete (2026-09-17, owner tested) |
| 10 | Application awareness | ✅ Complete (2026-09-17, owner approved) |
| 11 | Final performance optimization | ✅ Complete (2026-09-17, owner approved) |
| 12 | Packaging | ✅ Complete (2026-09-17, installed, owner approved) |
| 13 | Final audit | ✅ Complete (2026-09-17, owner reviewed; follow-up: languages → Phase 14) |
| 14 | Languages: Hindi (Devanagari), Hinglish, German | 🟡 Complete + benchmarked 2026-09-18; awaiting owner live test |

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

## Phase 5 — Text insertion ✅
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
- [x] Owner: long dictation, app switching and paste behavior confirmed working (2026-09-17); declined a "paste last transcript" hotkey
      (Copy Last Transcript in the menu is enough)
- [x] **Owner request: ⌥ alone as the trigger**: hold ⌥ to dictate; double-tap ⌥ → hands-free, next ⌥ press
      finishes; quick single tap discarded; chords (⌥+key, ⌥+other modifier) cancel silently. Core `ModifierKeyGesture` (9 tests);
      `ModifierKeyMonitor` = listen-only event taps (modifier changes always; key-down tap enabled only while ⌥ is held, key identity
      never read); falls back to ⌥Space with a menu warning if Input Monitoring is missing; setting `dictationTrigger` (`option` default |
      `hotkeyCombination`). Gesture only finishes/cancels recordings it started. Idle unchanged: 0.00 s CPU / 30 s, 6 wakeups, 13 MB
- [x] Owner tested the ⌥ trigger (2026-09-17): hold, hands-free double-tap, ⌥ to finish, app switch in hands-free (VS Code → Chrome),
      shortcuts unaffected. Latency log bug (always 0 ms: nanosecond timestamp vs mach ticks) fixed; measure in Phase 6
- Phase 6 notes: footprint with model loaded grew 1,185 → ~1,500 MB during the owner session (investigate); restore delay
  250 ms unproblematic so far

## Phase 6 — Fast path optimization ✅
- [x] Fitted encoder window (`audio_ctx`): 2–3× faster but failed the gate (empty/truncated transcripts) → rejected, switch removed
- [x] **Core ML encoder on the Neural Engine: adopted.** Same accuracy (49/50 + 7/7 identical), −25% clip latency, live release → text
      544–700 ms (was 914–1,015). `fetch-models.sh whisper-coreml medium.en`; the load log names the encoder
- [x] Memory step (+292 MB once): decode-fallback hypothesis tested; not reproduced in 20 live dictations → watch, no change
- [x] Fixed: model size check didn't follow symlinks (a symlinked model was reported as damaged)
- [x] Cold vs warm: cold = warm latency (load 0.3 s runs during speech); load/unload cycles leak ~0.7 MB each → default unload 300 → 60 s
- [x] Residual ~187 MB after unload → owner chose the helper process: `voiceflow-stt` owns whisper.cpp; app 13–18 MB always; helper
      ready in 0.33–0.38 s per fresh process; release → text 606–764 ms; no orphans on app kill; accuracy identical (50/50, 7/7)
- [x] Owner real use (2026-09-17): ⌥ dispatch 0.22–1.66 ms; press → first audio 185–241 ms; release → pasted 1.09 s (32 s hands-free) /
      1.58 s (40 s hold); app 13–27 MB. Recording-start optimization not pursued (tens of ms) → PERFORMANCE.md §3.10
- **Phase 6 outcome:** short dictation release → text ~0.95 s → ~0.6–0.75 s (Core ML encoder); app memory ~190 MB+ → 13–27 MB
  (helper process); accuracy unchanged on both sets

## Phase 7 — Local LLM (Smart Mode) ✅
- [x] Candidates: Apple on-device model (FoundationModels, available here), llama.cpp with Qwen2.5 0.5/1.5/3B, Llama 3.2 1B,
      Gemma 3 1B (downloaded, SHA-256 verified). MLX not buildable without Xcode
- [x] Cleanup safety benchmark: 57 real transcripts + 15 traps; `CleanupScorer` + `vf-bench cleanup` (`--guarded`, `--rule-based`)
- [x] Finding: **every model violated the contract** (wrote poems/code, answered questions, changed meaning); Apple's model least (5/72)
- [x] `RuleBasedCleanup` (Core, no LLM): 0 unsafe, formatting 15.6% → 10.6%, instant → **on by default** (`cleanupTranscripts`)
- [x] `RewriteGuard` (Core): makes every model safe via fallback; observed unsafe outputs as tests
- [x] **Smart Mode = Apple on-device model + guard** (optional, off by default): 0 unsafe, 10.2%, +0.79 s, 7% fallback. Menu
      shows availability; prewarm at recording start; 5 s timeout; errors fall back
- [x] No llama.cpp dependency added
- [x] Live check: rewrites accepted in 877/1,181 ms; guard rejected an expanded 1-word rewrite
- Notes for Phase 8: Clean-mode Smart gain over rules is small; Developer/Prompt/Writing modes change more words and need
  per-mode guard policies (the current guard would reject most of their intended edits)

## Phase 8 — Text modes ✅
- [x] `TextMode` raw / clean (default) / developer / prompt / writing; setting `textMode` (legacy `cleanupTranscripts: false` → raw)
- [x] Menu: **Mode ▸** five modes + **Smart Rewrite** toggle (on-device model for Clean/Developer; `processingMode`). Prompt/Writing
      disabled with the reason when the on-device model is unavailable
- [x] `DeveloperFormatter` (rules): spoken symbols in unambiguous patterns, multi-word names, product casing; 0 unsafe on 72 real+trap
      and 54 spoken-form transcripts; spoken-form formatting 21.4% → 14.3%
- [x] `RewriteGuard.Policy`: strict (Clean/Developer) and content-preserving (Prompt/Writing: same content words in the same
      order, limited grammar-word insertion, terms kept, no expansion/code)
- [x] `prompts/prompt.json` (v2), `prompts/writing.json`; examples are guard-safe (tested)
- [x] `vf-bench modes prepare|report`; new `benchmarks/corpus/mode-traps.json` (15); spoken-form corpus generated by
      `make-cleanup-corpus.py`
- [x] Benchmark (ACCURACY §7): 0 traps through; fallback on real transcripts Developer+Smart 2/57, Prompt 6/57, Writing 7/57;
      +0.80–0.91 s mean. 41 accepted rewrites hand-reviewed: no meaning changes
- [x] Guard holes found in review and closed (order check; logic/modal/quantifier/pronoun swaps); Clean bug fixed ("Do not…?")
- [x] Clean: standalone "i" → "I"
- [x] 117 core tests + 3 app tests pass; app builds (6.1 MB) (first delivery)
- [x] Owner live test 1 (2026-09-17): Developer ✓, Writing ✓; Prompt and Clean + Smart Rewrite fell back (guard). Request: bullet
      points for spoken enumerations, in Clean too
- [x] Lists: `ListScaffold` (counting words removable only in front of 2+ list items), list rules in all three prompts, Clean/
      Developer line breaks only around lists, Developer formatting per line. Prompt/Writing 4/4 test enumerations, Clean 1/4 + the
      owner's own dictation (ACCURACY §7.3)
- [x] Guard holes found in review and closed: dropped "you"; dropped causal "so"; single added word ("never"/"not") and article
      replaced by any word in strict scoring (Phase 7 re-scored: Apple unchanged)
- [x] 126 core tests + 3 app tests pass
- [x] Owner approved Phase 8 (2026-09-17)
- Known: Prompt often drops "I want you to"/an intro sentence and falls back; rejected rewrites on long dictations cost up to 3.4 s
  for nothing (PERFORMANCE §5.2) → candidates for Phase 11
- Not in Phase 8 (→ Phase 9): "engine x dot conf"/"nginx.com" → nginx.conf, "kube control" → kubectl, Helm; per-app automatic mode
  (→ Phase 10)

## Phase 9 — Developer intelligence ✅
- [x] Inspected owner-recording errors: nginx.com, kube control, help/Helm, spoken identifiers, env var casing
- [x] `DeveloperCorrections` (context-gated rules; Developer + Code modes): kubectl, git, Helm, nginx.conf, React hooks, event
      props, verb-first function names, env vars, domains/localhost ports, explicit case cues
- [x] Code mode (`CodeFormatter`): spoken symbols/operators/brackets/quotes, flags, paths, case cues, no sentence styling; menu item
- [x] `UserDictionary` (`dictionary.json`: terms + replacements; speech prompt, guard protection; menu "Open Dictionary File…")
- [x] `benchmarks/corpus/developer-intel.json` (49) + `vf-bench modes intel`; held-out Phase 8 vs 9 comparison (ACCURACY §8):
      0 over-corrections; real transcripts formatting 10.8% → 10.6%, spoken forms 14.3% → 12.3%
- [x] Over-corrections found and fixed: "local host dot com event"; case cue crossing a comma in the owner's long-form transcript
- [x] 134 core tests + 3 app tests pass; STT prompt unchanged with an empty dictionary (no STT re-gate needed)
- [x] Owner tested Developer corrections, Code mode and the dictionary; approved (2026-09-17)
- Not handled (no safe context): "we don't need help for now", "forms" vs "form's", Hinglish

## Phase 10 — Application awareness ✅
- [x] `AppModePolicy` (Core): owner rule → browser AI tab → built-in bundle table → menu mode; `modeByApp` (default on), `appModes`
      (tolerant decoding); 6 tests
- [x] `TargetApp` (app): receiving app (paste target), browser focused-window title via Accessibility (100 ms timeout, never logged)
- [x] Pipeline: mode resolved when the transcript is ready; prewarm for the app in front at recording start; log line
      `mode <m> (<source>) for <bundle id>, detected in <ms>`
- [x] Menu: resolved mode for the app in front, "Choose Mode by App", "For <App> ▸ Automatic / modes"
- [x] 139 core tests + 3 app tests pass
- [x] Owner test (2026-09-17): VS Code, WhatsApp, Chrome ChatGPT/Claude tab, Notes: correct mode every time; detection 0.00–0.10 ms
- [x] Owner-reported grammar issue ("Apples Notes"): apostrophe restoration after rewrites, contraction rules, agreement and
      sentence-opener allowances in the strict guard, one narrow prompt sentence; broad grammar prompt tried and reverted
      (more rejections) (ACCURACY §7.4)
- [x] 143 core tests + 3 app tests pass
- [x] Owner approved Phase 10 (2026-09-17)
- Found for Phase 11: model modes take 3–4 s end to end (rewrite 1.9–2.6 s); rejected rewrites waste that time
- Terminals default to Developer (spec allows Raw/Developer); Code available per terminal

## Phase 11 — Final performance optimization ✅
- [x] Model-mode latency analysis: ≈ 0.5 s + 0.026 s/output word; long dictations slowest and most rejected
- [x] Measured and rejected: parallel sentence chunks (2.9 s vs 2.1 s whole); streaming early rejection (≤ 0.15 s saved, false rejections)
- [x] Adopted: rewrite with the prewarmed session (−0.12 to −0.31 s); skip the model for ≤ 10-word dictations in Clean/Developer/Prompt
      (~0.65 s saved; gain ≤ 0.4 points, Prompt was worse); Writing unchanged
- [x] Recording indicator turns red when real audio flows (first-word clipping mitigation; AirPods ~0.5 s)
- [x] Audit (PERFORMANCE §5.5): idle 0 CPU / 12–13 MB; launch 123 ms; recording start 66–87 ms; STT on owner set identical
      50/50, mean 0.598 s; helper 1.1–1.2 GB only while loaded; app 6.6 MB; models in use 1.39 GB
- [x] 144 core tests + 3 app tests pass
- [x] Owner: working fine in use; approved (2026-09-17). Ollama gemma2:9b discussed and not pursued (memory/latency, localhost server)
- Optional (owner's call): delete 5.0 GB of benchmark-only STT models

## Phase 12 — Packaging ✅
- [x] Bundle: version 1.0.0, build number from git, app icon (`scripts/assets/make-icon.swift`), category, microphone text covers
      hands-free; `BuildInfo` reads the bundle
- [x] `scripts/install.sh` (framework check, `--with-models`, build, tests, ~/Applications or `--applications`, launch) and
      `scripts/uninstall.sh [--purge]`; both tested against a temporary folder (signature verified, installed copy runs)
- [x] Menu: Open at Login (`SMAppService.mainApp`), Copy Diagnostics; `VoiceFlow --diagnostics`; Neural Engine encoder missing warning
- [x] Crash handling verified: helper killed mid-transcription → error with Retry, app alive, next dictation recovers
- [x] 146 core tests + 3 app tests pass
- [x] Owner request: full app UI + Wispr Flow–style pill (beyond spec §17, owner decision):
      window (Home/Modes/Apps/Dictionary/Settings/About, Dock icon only while open, shown on first launch, ⌘O, reopen) and
      draggable non-activating pill (level bars, finish/cancel, Transcribing/Rewriting/Pasted/errors) with saved position
- [x] Verified: screenshots of all window sections and the pill while recording/after; idle unchanged (13 MB, 0 CPU); window
      open 0.23 % CPU / 31 MB; 147 core + 5 app tests pass (incl. saved-position fallback)
- [x] Installed to ~/Applications/VoiceFlow.app (2026-09-17, owner request after seeing two Spotlight results): development builds
      now go to `build/Products.noindex/` (not indexed) with a `build/VoiceFlow.app` symlink; build copy unregistered
- [x] Owner installed and approved Phase 12 (2026-09-17)

## Phase 13 — Final audit ✅
- [x] Accuracy: installed helper on owner recordings WER 1.1%, terms 97.4%, 0 invented; identical to the gate (50/50, 7/7); text modes
      and developer corrections unchanged (0 unsafe, 0 over-corrections)
- [x] Performance: idle 13 MB / 0.01 s CPU per minute / 0 GPU; launch 101 ms; STT mean 0.63 s per clip
- [x] Privacy: no network code or frameworks; 0 sockets and 0 files during a full dictation with rewrite; 0 log lines with spoken words
- [x] Reliability: damaged model (live, with speech), missing model (live), helper crash (Phase 12), rewrite/paste/permission failures
      (tests; added `microphoneDeniedRecoversAfterAccessIsGranted`, `pasteFailureIsReportedAndDismissible`)
- [x] UX checklist; known limitations listed in docs/AUDIT.md
- [x] 149 core + 5 app tests pass
- [x] Owner reviewed (2026-09-17). Requests: add Hindi (Devanagari), Hinglish, German (Phase 14); keep the 5.0 GB benchmark models until the owner explicitly says to delete them

## Phase 14 — Languages: Hindi (Devanagari), Hinglish, German 🟡 (awaiting owner Hindi recordings)
Owner decisions (2026-09-17): Auto-detect by default + manual choice + switch shortcut; owner records Hindi/Hinglish (German judged on
synthetic voices only); Hindi keeps English words in Latin; benchmark models kept until the owner says otherwise.
- [x] Corpus `benchmarks/corpus/multilingual.json`: German 26, Hindi 24 (scored as Devanagari and Hinglish); prompts; `record.sh --hindi`
- [x] Harness: `--language`, `auto3` detection, `--detect-only`; `stt-multilingual.sh`; scorer: Devanagari tokens, `--hinglish` spelling tolerance
- [x] Synthetic shortlist (3 German voices, Lekha): German large-v3 q5_0 + prompt 8.3% WER / 79.6% terms; Hindi Devanagari
      large-v3 + prompt ~9–12%, turbo + prompt 12%; Whisper can't write Hinglish directly (best 41%) → Devanagari + rules
- [x] `HindiTransliteration`: Devanagari → Hinglish (lexicon + code-point romanization, schwa deletion) 6.8–10% WER; loanwords → Latin; danda
- [x] Detection: large-v3-turbo 100/100 with widest margins; Neural Engine encoder 1.05 s → 0.48 s; base 57 ms but thin margins (cascade possible)
- [x] Neural Engine encoders: large-v3 German 2.0 → 1.1 s/clip, Hindi 2.4 → 1.6 s, same accuracy
- [x] App: language setting (Auto/English/German/Hindi/Hinglish), Hindi script for Auto, ⌃⇧L cycles language (pill notice), menu +
      window controls, pill language badge; helper holds several models + language detection; English still uses medium.en;
      per-language cleanup (German/Hindi fillers, questions, danda); on-device rewrite English/German only (German prompt: never translate)
- [x] German model modes: 0 traps accepted (answers, poems, code, translations rejected); small gain, ~30% fallback
- [x] `--measure-files` (dictate audio files without the microphone); live routing: EN/DE/HI detected correctly; Auto adds ~0.5 s
- [x] Owner recorded 24 Hindi clips (2026-09-18). Decision: **Hindi/Hinglish = large-v3-turbo q8_0 + Devanagari prompt**
      (WER 5.7% Devanagari / 3.5% Hinglish, terms 96.2%, 0.65 s; also the detector → one model fewer in Auto);
      **German = large-v3 q5_0 + German prompt** (synthetic only); detection = turbo (24/24 on owner Hindi, margin ≥ 0.84)
- [x] Docs: ACCURACY §9, PERFORMANCE §5.7, ARCHITECTURE §3.9, README, DEVELOPMENT
- [ ] **Owner:** live test (dictate Hindi/Hinglish/German, ⌃⇧L switching, Auto in real apps) and approve Phase 14

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
| 2026-09-17 | Rule-based cleanup on by default; Smart Mode = Apple on-device model + RewriteGuard (optional); no llama.cpp | All LLMs violated the transform-only contract; guard makes them safe; rules give most of the gain instantly | ACCURACY §6, ARCHITECTURE §3.5 |
| 2026-09-17 | whisper.cpp in a helper process (`voiceflow-stt`) that exits 60 s after last use | Owner approved; app stays at 13–18 MB; no latency cost; frees whisper.cpp's leftover and leaked memory | ARCHITECTURE §Processes |
| 2026-09-17 | Unload STT model 60 s after last use (was 300 s) | Cold dictation as fast as warm; ~0.7 MB leak per load cycle favors bursts sharing a load | PERFORMANCE §3.8 |
| 2026-09-17 | Core ML (Neural Engine) Whisper encoder | Same accuracy, −17…25% latency; `audio_ctx` fitting rejected (fails gate) | PERFORMANCE §3.5–3.6 |
| 2026-09-17 | Trigger = ⌥ alone (hold; double-tap for hands-free), listen-only event taps; ⌥Space fallback | Owner request (Wispr Flow–style); no idle cost measured | ARCHITECTURE §3.3 |
| 2026-09-17 | Segment dictations > 29 s at pauses into independent chunks | Owner's long dictation lost speech and invented a loop; long-form WER 22.7% → 0.7%, no short-clip regression | ACCURACY §5.9 |
| 2026-09-17 | Text modes: Raw / Clean (default) / Developer (rules) / Prompt / Writing (on-device model); Smart Rewrite toggle for Clean/Developer | Rules are instant and can't change meaning; model modes only behind a per-mode guard | ARCHITECTURE §3.5.1, ACCURACY §7 |
| 2026-09-17 | Prompt/Writing guard = same content words in the same order; connectives, modals, quantifiers, "from" are content; pronouns may only be dropped | Hand review found swaps a set check would accept | ACCURACY §7.2 |
| 2026-09-17 | Spoken enumerations become lists (Clean + Smart Rewrite, Prompt, Writing); guard accepts removing only counting words in front of 2+ items | Owner request after live test | ACCURACY §7.3 |
| 2026-09-17 | Developer corrections = context-gated rules (no global lexicon, no model); Code mode (rules); owner dictionary file | Spec §13 conservative; held-out check 0 over-corrections | ARCHITECTURE §3.5.2, ACCURACY §8 |
| 2026-09-17 | Mode chosen per receiving app: owner rule → browser AI tab (window title via Accessibility) → built-in table → menu mode; terminals → Developer | Spec §Phase 10; no new permission; title never logged | ARCHITECTURE §3.5.3 |
| 2026-09-17 | Rewrite in the prewarmed session; no model for ≤ 10-word Clean/Developer/Prompt dictations; red icon when audio flows | Measured −0.12…−0.31 s and ~0.65 s with ≤ 0.4 pt formatting cost; chunking/early abort rejected | PERFORMANCE §5.4–5.5 |
| 2026-09-17 | Packaging: script install to ~/Applications, SMAppService login item, local diagnostics; no installer/daemon/notarization | Spec Phase 12 "no unnecessary installers or services"; personal build | ARCHITECTURE §3.7 |
| 2026-09-17 | Full app window + draggable floating pill with saved position (owner request; spec §17 said minimal menu-bar UI) | Owner decision; built to cost nothing when closed/idle | ARCHITECTURE §3.8, PERFORMANCE §5.6 |
| 2026-09-18 | Hindi/Hinglish = large-v3-turbo q8_0 + Devanagari prompt (also the detector); German = large-v3 q5_0; Hinglish by rule transliteration | Owner recordings: 5.7%/3.5% WER, terms 96.2%, 2.5× faster than large-v3; Whisper can't write Hinglish directly | ACCURACY §9 |
| 2026-09-16 | Carbon RegisterEventHotKey; Esc cancel registered only while recording | Press+release, no permission, zero idle cost | ARCHITECTURE §3.3 |
| 2026-09-16 | Clipboard + ⌘V with full snapshot/restore; never lose speech | Works in Electron/terminals/browsers | ARCHITECTURE §3.4 |
| 2026-09-16 | llama.cpp in-process (provisional); Ollama rejected | No daemon/IPC; MLX re-evaluated in Phase 7 | ARCHITECTURE §3.5 |

## Session handoff notes
_Overwrite at the end of every session._

- **Last session (2026-09-17):** Phases 0–10 complete (owner approved). Phases 0–11 complete. Phase 12 complete and installed. Phase 13 audit complete; awaiting approval.
- **Models on this machine** (`~/Library/Application Support/VoiceFlow/models/`): **in use:** whisper medium.en-q8_0 +
  ggml-medium.en-encoder.mlmodelc. Benchmark-only (deletable on request): whisper tiny.en, base.en, small.en, large-v3-turbo,
  large-v3-turbo-q8_0 (STT alternate), distil-large-v3; parakeet tdt-0.6b-v3-q8_0.
- **Owner recordings:** `benchmarks-output/audio/human/macbook-mic/` (50 clips + `spoken-overrides.json`, gitignored). Results cached in
  `benchmarks-output/results/human/`. Rerunning `scripts/bench/stt.sh human` re-scores instantly.
- **Mode benchmark data:** `benchmarks-output/results/modes/` (prepared inputs, model JSONL per mode, `report.md` with every
  accepted/rejected rewrite). Re-score after guard changes with `vf-bench modes report … --results …` (no model rerun needed).
- **Next action:** owner live-tests Phase 14 (Hindi/Hinglish/German, ⌃⇧L, Auto) and approves. Do NOT delete benchmark models until the owner explicitly asks.
