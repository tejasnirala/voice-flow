# VoiceFlow

A local-only macOS menu-bar dictation utility built for software development.

**Hold ⌥ → speak naturally → release → accurate text appears in the focused app.** Double-tap ⌥ for hands-free.
Speech recognition and optional cleanup run entirely on your Mac. No cloud, no telemetry, no stored audio
or transcripts.

> **Status:** Phase 6 complete: hold ⌥ (or double-tap for hands-free) → speak → text pasted in ~0.6–1.1 s, clipboard preserved. The app uses ~13–27 MB; speech recognition runs in an on-demand helper process. Phase 7 complete: rule-based cleanup by default, optional guarded Smart Mode. Phase 8: Raw / Clean / Developer / Prompt / Writing text modes.
> See [`docs/PROGRESS.md`](docs/PROGRESS.md).

## Priorities
1. **Transcription accuracy**, especially developer vocabulary (Next.js, PostgreSQL, `getUserById`,
   `docker compose up`, `.env.local` …)
2. Latency 3. Resource efficiency (near-zero idle CPU/GPU, low idle RAM) 4. Features

## Text modes
Choose in the menu bar (**Mode**). Every mode preserves meaning; anything a model changes is checked by a deterministic
guard, and a rejected rewrite falls back to the rule-based text.
- **Raw:** exactly what speech recognition produced.
- **Clean (default):** rules remove hesitations and stutters and fix capitalization and end punctuation. Instant.
- **Developer:** Clean + spoken symbols and developer casing by rule ("package dot json" → `package.json`,
  "dash dash save" → `--save`, "user underscore id" → `user_id`, "postgres q l" → PostgreSQL). Instant.
- **Prompt:** Apple's on-device model turns spoken thoughts into a clear prompt for an AI assistant (+~1 s). Spoken
  enumerations ("two things: one is …, the second is …") become bullet lists here, in Writing, and in Clean with Smart Rewrite.
- **Writing:** Apple's on-device model turns speech into polished prose (+~1 s).
- **Smart Rewrite** (toggle): also runs the on-device model for Clean and Developer, with a word-for-word guard (+~0.8 s).
  Prompt and Writing use a content-preserving guard: sentences may be restructured, but no content word may be added,
  dropped or replaced.

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
