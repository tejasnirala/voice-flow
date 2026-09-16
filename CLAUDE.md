# VoiceFlow — instructions for Claude sessions

Offline, ultra-low-latency macOS menu-bar dictation utility (Swift 6 + AppKit, SwiftPM).

## Start of every session
1. Read `docs/PROGRESS.md` — current phase, what's next, leftovers, handoff notes.
2. The requirements contract is `docs/SPEC.md`. Priorities: latency > resource usage > offline
   privacy > reliability > quality > developer intelligence > UI > features.
3. Relevant architecture decisions are in `docs/architecture/`.

## Working rules
- Work one phase at a time. After each phase: build → `scripts/test.sh` → relevant benchmark →
  verify → inspect `git diff` → update docs → **update `docs/PROGRESS.md`** (status table,
  checklist, leftovers, decision log, handoff notes) → commit → continue.
- If a session ends mid-phase, mark the phase 🟡 in PROGRESS.md and record exactly what remains.
- Never fabricate benchmark numbers; record only what was measured on this machine.
- Never commit models, audio, `Vendor/`, `build/`, `.build/`, or secrets.
- Don't add dependencies without an entry in `docs/dependencies.md`.
- Source folders under `VoiceFlow/` are created when they first get code. Add each new folder to
  `sources` of its target **and** `exclude` of the other target in `Package.swift`.

## Commands
- Build app bundle: `scripts/build-app.sh` (release) / `scripts/build-app.sh debug`
- Tests: `scripts/test.sh` (plain `swift test` fails with Command Line Tools only)
- Native runtimes: `scripts/fetch-deps.sh` · Models: `scripts/fetch-models.sh whisper base.en`
- STT benchmark: `scripts/bench/make-audio.sh && scripts/bench/stt.sh`

## Environment gotchas
- No Xcode installed (Command Line Tools only): no `xcodebuild`, no offline `metal` compiler.
- whisper.cpp Metal shaders compile at runtime: ~15 s on the first load per new binary, then cached.
