# VoiceFlow — Progress Tracker

> **Single source of truth for where the project stands.**
> Read this first at the start of every session. Update it at the end of every phase
> (and whenever a phase is paused mid-way). The full original spec lives in
> [`docs/SPEC.md`](SPEC.md).

## Status at a glance

| Phase | Name | Status | Commit |
|---|---|---|---|
| 0 | Machine & architecture discovery | ✅ Complete (2026-09-16) | `chore: initialize project` |
| 1 | Lightweight native shell | ⏭️ **Next** | — |
| 2 | Global hotkey | ⬜ Not started | — |
| 3 | Audio | ⬜ Not started | — |
| 4 | Local STT | ⬜ Not started | — |
| 5 | Text insertion (**core product works**) | ⬜ Not started | — |
| 6 | Performance pass | ⬜ Not started | — |
| 7 | Local LLM | ⬜ Not started | — |
| 8 | Processing modes | ⬜ Not started | — |
| 9 | Developer optimization | ⬜ Not started | — |
| 10 | Application awareness | ⬜ Not started | — |
| 11 | Performance optimization round 2 | ⬜ Not started | — |
| 12 | Packaging | ⬜ Not started | — |
| 13 | Final offline audit | ⬜ Not started | — |

Legend: ✅ complete · 🟡 in progress · ⏭️ next · ⬜ not started · ⚠️ blocked

## Per-phase checklist (from the spec's development rule)

Every phase ends with: build → tests → relevant benchmark → verify functionality →
inspect `git diff` → update docs **and this file** → fix issues → commit → continue.

---

## Phase 0 — Machine & architecture discovery ✅

**Done**
- Machine inspected → [`environment.md`](environment.md)
- Decisions made and documented → [`architecture/`](architecture/)
- SwiftPM project (no Xcode — only Command Line Tools installed) with `VoiceFlowCore` library,
  `VoiceFlow` menu-bar executable, Swift Testing test target
- `scripts/build-app.sh` assembles + signs `build/VoiceFlow.app` (68 KB); launches as `LSUIElement`
- `scripts/test.sh` (works around CLT not finding the Swift Testing macro plugin)
- `scripts/fetch-deps.sh` (whisper.cpp xcframework, SHA-256 pinned), `scripts/fetch-models.sh`
- Preliminary benchmarks on synthetic (`say`) audio → [`benchmarks/stt.md`](benchmarks/stt.md),
  [`benchmarks/llm.md`](benchmarks/llm.md); reproducible via `scripts/bench/`

**Left over / carried forward**
- Benchmarks used synthetic TTS audio. Real-voice recordings needed in Phase 4 (own accent,
  Hinglish, built-in mic vs AirPods).
- Formal startup/idle measurement (Phase 1 — only a sanity check was done: 13–14 MB footprint, 0.0% CPU).
- Only `VoiceFlow/App` and `VoiceFlow/Core` exist; the other spec folders are created as they get code.
- Hindi/Hinglish: not yet tested (only `.en` Whisper models downloaded; multilingual `base`/`small` needed).
- Code-signing identity "VoiceFlow Dev" not yet created (needed before Phase 3/5 so TCC grants survive rebuilds).

## Phase 1 — Lightweight native shell ⏭️ NEXT

**To do**
- [ ] Menu-bar UI per spec §24 (status line, Mode submenu, Smart Processing toggle, Settings, Quit)
- [ ] `Configuration` (Codable, `~/Library/Application Support/VoiceFlow/config.json`, defaults, tests)
- [ ] `PipelineState` state machine (IDLE→RECORDING→TRANSCRIBING→PROCESSING→INSERTING→IDLE, ERROR, CANCELLED) with deterministic transition tests
- [ ] `ProcessingMode` enum (Raw/Clean/Developer/Prompt/Writing) — selection + persistence only, no processing yet
- [ ] Permission foundation: `PermissionsService` (microphone via AVCaptureDevice auth status, Accessibility via `AXIsProcessTrusted`), surfaced in menu
- [ ] `PerformanceMonitor` skeleton (monotonic clock spans, os_signpost; no transcript content in logs)
- [ ] `scripts/measure-idle.sh`: startup time, idle RSS/footprint, idle CPU, idle GPU (per-process `accumulatedGPUTime` from `ioreg`, no sudo)
- [ ] Record → `benchmarks/startup.md`, `benchmarks/memory.md`
- [ ] Create "VoiceFlow Dev" self-signed code-signing identity (see `development.md`)

## Phase 2 — Global hotkey
- Carbon `RegisterEventHotKey` for ⌥Space with `kEventHotKeyPressed` + `kEventHotKeyReleased` (no polling, no Accessibility needed)
- Measure hotkey detection latency

## Phase 3 — Audio
- AVAudioEngine input tap → in-memory 16 kHz mono Float32 via AVAudioConverter
- Measure recording startup latency (built-in mic vs AirPods vs iPhone Continuity mic — the default input on this machine is currently the iPhone)
- Silence / too-short detection (RMS/energy gate) before any STT

## Phase 4 — Local STT
- Integrate whisper.cpp via `Vendor/whisper.xcframework` binary target
- Re-run `scripts/bench/stt.sh` + real-voice clips; decide base.en vs small.en; test Apple SpeechTranscriber with contextual strings; test multilingual model for Hinglish
- Write final `benchmarks/stt.md`

## Phase 5 — Text insertion
- `TextInsertionService`: snapshot all pasteboard items/types → write text (+ transient/concealed markers) → CGEvent ⌘V → restore if changeCount unchanged

## Phases 6–13
See spec (`docs/SPEC.md` §41). Notes captured so far:
- **Phase 6:** Metal shader compile costs ~15 s once per new binary (see `benchmarks/stt.md`). Investigate warming in background at low priority after launch vs CPU fallback for first request.
- **Phase 7:** Qwen2.5-1.5B-Instruct Q4_K_M needs few-shot prompt + output guard (it wrote a TypeScript code block with a zero-shot prompt). Reuse KV cache of the fixed system/few-shot prefix to cut ~200 ms prompt eval. Consider ggml symbol duplication when linking both whisper and llama frameworks.

---

## Decision log

| Date | Decision | Why | Doc |
|---|---|---|---|
| 2026-09-16 | Swift 6 + AppKit, SwiftPM only, script-built .app | Native APIs, tiny binary, no Xcode installed (user chose not to install) | architecture/overview.md |
| 2026-09-16 | whisper.cpp (prebuilt xcframework) as primary STT candidate | Measured: base.en 0.08–0.26 s, small.en 0.22–0.82 s on Metal; in-process; no daemon | architecture/stt.md |
| 2026-09-16 | Apple SpeechTranscriber kept as benchmarked alternative | Zero model files, ~20 MB in-process, but worse on tech vocab in initial test | architecture/stt.md |
| 2026-09-16 | llama.cpp in-process as LLM runtime; Ollama rejected; MLX-Swift ruled out | Ollama = localhost daemon; MLX-Swift needs Xcode to build Metal shaders | architecture/llm.md |
| 2026-09-16 | Carbon RegisterEventHotKey for hotkey | Event-driven press+release, no Accessibility/Input Monitoring permission | architecture/input.md |
| 2026-09-16 | Clipboard + synthetic ⌘V for insertion, with full pasteboard restore | Works in Electron/terminals/browsers where AX value setting fails | architecture/input.md |

## Session handoff notes

_Update this at the end of every session (overwrite, don't append)._

- **Last session (2026-09-16):** Completed Phase 0. Models already downloaded on this machine:
  whisper `tiny.en`, `base.en`, `small.en`; LLM `qwen2.5-1.5b-instruct-q4_k_m`.
- **Start next session with:** Phase 1 checklist above.
