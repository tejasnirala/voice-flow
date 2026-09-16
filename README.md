# VoiceFlow

A tiny, offline macOS menu-bar utility that turns your voice into text almost instantly.

**Hold ⌥ Space → speak → release → text appears in the focused app.**
Speech recognition (whisper.cpp) and optional cleanup (a small local LLM) run entirely on your
Mac. No cloud, no telemetry, no stored audio or transcripts.

> **Status:** Phase 0 complete (architecture + buildable shell). Not usable for dictation yet.
> See [`docs/PROGRESS.md`](docs/PROGRESS.md).

## Design goals (in priority order)
1. Latency · 2. Lightweight (≈0% idle CPU/GPU, small RAM) · 3. Offline privacy · 4. Reliability
· 5. Transcription quality · 6. Developer-aware formatting · 7. UI · 8. Features

## Modes
- **Fast Mode** (default): audio → Whisper → paste.
- **Smart Processing**: audio → Whisper → local LLM (Clean / Developer / Prompt / Writing) → paste.

## Quick start (development)
```sh
scripts/fetch-deps.sh
scripts/fetch-models.sh whisper base.en
scripts/build-app.sh && open build/VoiceFlow.app
```
Needs only the Command Line Tools. Details in [`docs/development.md`](docs/development.md).

## Documentation
| Doc | Contents |
|---|---|
| [`docs/SPEC.md`](docs/SPEC.md) | Product and engineering requirements |
| [`docs/PROGRESS.md`](docs/PROGRESS.md) | Phase status, next steps, decision log |
| [`docs/architecture/`](docs/architecture/) | Overview, STT, LLM, audio, input, performance |
| [`docs/benchmarks/`](docs/benchmarks/) | Measured results (this machine only) |
| [`docs/environment.md`](docs/environment.md) | Development machine inventory |
| [`docs/security.md`](docs/security.md) | Permissions, data handling, network behavior |
| [`docs/dependencies.md`](docs/dependencies.md) | Every dependency and why |
