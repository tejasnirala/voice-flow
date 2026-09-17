# VoiceFlow — instructions for Claude sessions

Local-only, accuracy-first macOS menu-bar dictation utility (Swift 6 + AppKit, SwiftPM, whisper.cpp).

## Start of every session
1. Read `docs/PROGRESS.md`: current phase, what's next, leftovers, handoff notes.
2. The requirements contract is `docs/SPEC.md` (v2). Priority order, never reversed:
   **accuracy > latency > resource efficiency > features.**
3. Design and decisions: `docs/ARCHITECTURE.md`. Measured data: `docs/ACCURACY.md`, `docs/PERFORMANCE.md`.

## Working rules
- One phase at a time. Per phase: inspect → explain plan → implement only that phase → build →
  `scripts/test.sh` → relevant benchmark → fix → review → check CPU/RAM impact → update docs →
  **update `docs/PROGRESS.md`** → show the owner what changed → commit → **stop and wait for approval**.
- If a session ends mid-phase, mark the phase 🟡 in PROGRESS.md and record exactly what remains.
- Never fabricate benchmark numbers. Record only what was measured on this machine, with date and conditions.
- Never pick an STT model because it's smaller or faster if it fails the accuracy threshold (ACCURACY.md).
- The LLM must never hide or "fix" bad STT, or invent technical terms.
- Never commit models, audio, `Vendor/`, `build/`, `.build/`, `benchmarks-output/`, or secrets.
- New dependencies need a justification in ARCHITECTURE.md §6.

## Commands
- Build app: `scripts/build-app.sh` · Tests: `scripts/test.sh` (plain `swift test` fails with CLT only)
- Runtimes: `scripts/fetch-deps.sh` · Models: `scripts/fetch-models.sh whisper large-v3-turbo-q8_0`
- STT benchmark: `scripts/bench/make-audio.sh && scripts/bench/stt.sh synthetic`;
  owner voice: `scripts/bench/record.sh <mic-label>` then `scripts/bench/stt.sh human`

## Environment gotchas
- No Xcode (Command Line Tools only): no `xcodebuild`, no offline `metal` compiler.
- whisper.cpp Metal shaders compile at runtime (~15 s the first time for a new binary, then cached).
- Always `whisper_free`/`parakeet_free` before process exit, or ggml's Metal teardown asserts.
