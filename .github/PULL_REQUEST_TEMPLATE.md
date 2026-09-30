## What this changes

<!-- One or two sentences. Link the issue if there is one. -->

## Why

<!-- The problem it solves. -->

## Measurements

<!--
Anything that can affect recognition or text quality needs numbers: which benchmark you ran, on what, and the before/after.
See docs/DEVELOPMENT.md for the commands. Write "not applicable" if the change can't affect quality.
-->

## Checklist

- [ ] `scripts/test.sh` passes
- [ ] `scripts/build-app.sh` succeeds and the app still works
- [ ] Tests added or updated
- [ ] Docs updated (`docs/ARCHITECTURE.md`, `docs/ACCURACY.md`, `docs/PERFORMANCE.md`, README) where relevant
- [ ] No audio, transcripts, models or secrets committed
- [ ] Keeps the project rules: local only, never stores or logs what the user says, rewrites can't change the user's words
