# VoiceFlow

A local-only macOS menu-bar dictation utility built for software development.

**Hold ⌥ → speak naturally → release → accurate text appears in the focused app.** Double-tap ⌥ for hands-free.
Speech recognition and optional cleanup run entirely on your Mac. No cloud, no telemetry, no stored audio
or transcripts.

> **Status:** Phase 6 complete: hold ⌥ (or double-tap for hands-free) → speak → text pasted in ~0.6–1.1 s, clipboard preserved. The app uses ~13–27 MB; speech recognition runs in an on-demand helper process. Next: optional local LLM cleanup (Phase 7).
> See [`docs/PROGRESS.md`](docs/PROGRESS.md).

## Priorities
1. **Transcription accuracy**, especially developer vocabulary (Next.js, PostgreSQL, `getUserById`,
   `docker compose up`, `.env.local` …)
2. Latency 3. Resource efficiency (near-zero idle CPU/GPU, low idle RAM) 4. Features

## Modes
- **Fast Mode:** audio → local STT → paste.
- **Smart Mode:** audio → local STT → small local LLM (conservative cleanup, never guesses) → paste.

## Quick start (development)
```sh
scripts/fetch-deps.sh
scripts/fetch-models.sh whisper medium.en-q8_0
scripts/build-app.sh && open build/VoiceFlow.app
scripts/test.sh
```
Needs only the Command Line Tools. See [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md), including how to run
the accuracy benchmark on your own voice.

## Documentation
| Doc | Contents |
|---|---|
| [`docs/SPEC.md`](docs/SPEC.md) | Requirements (v2) |
| [`docs/PROGRESS.md`](docs/PROGRESS.md) | Phase status, next steps, decision log, session handoff |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Machine, stack, alternatives, STT decision, privacy, dependencies |
| [`docs/ACCURACY.md`](docs/ACCURACY.md) | Benchmark corpus, metrics, threshold, results |
| [`docs/PERFORMANCE.md`](docs/PERFORMANCE.md) | Measurement methodology and results |
| [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md) | Setup, commands, benchmarks, gotchas |
