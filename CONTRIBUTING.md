# Contributing to VoiceFlow

Thanks for your interest. VoiceFlow is a personal, local-only dictation utility for macOS, built accuracy-first. This
document explains how to build it, what the project's rules are, and what a good change looks like.

## Requirements

- **macOS 27 (Tahoe) or later to build the app.** The app uses APIs from recent SDKs (`installAudioTap`, FoundationModels).
  The pure-logic `VoiceFlowCore` target builds on older macOS.
- **Apple Silicon.** The speech runtime ships arm64 only.
- **Command Line Tools** (`xcode-select --install`). Xcode is not required and is not used.
- Apple Intelligence enabled if you work on the model-based modes (Prompt, Writing, Smart Rewrite).

## Setup

```sh
scripts/fetch-deps.sh                                   # whisper.cpp xcframework → Vendor/ (checksum verified)
scripts/fetch-models.sh whisper medium.en-q8_0          # English model (see README → Languages for the rest)
scripts/fetch-models.sh whisper-coreml medium.en
scripts/build-app.sh && open build/VoiceFlow.app
scripts/test.sh                                         # unit tests (plain `swift test` fails with CLT only)
```

`scripts/install.sh` installs to `~/Applications`; `scripts/uninstall.sh [--purge]` removes it.

## Project rules

These come from the project's specification (`docs/SPEC.md`) and are not negotiable in a pull request:

1. **Accuracy > latency > resource use > features.** Never trade accuracy for speed. A model is never chosen because it is
   smaller or faster if it fails the accuracy threshold in `docs/ACCURACY.md`.
2. **Local only.** No network calls at runtime, no telemetry, no accounts. Models are downloaded by setup scripts only.
3. **Never store audio or transcripts**, and never log them. Logs contain metadata only (timings, counts, bundle IDs).
4. **The rewrite must never change your words.** Model rewrites pass a deterministic guard; anything that adds, drops,
   replaces or reorders content is rejected and the rule-based text is used instead.
5. **Never fabricate benchmark numbers.** Record only what you measured, on which machine, with the date and conditions.

## Making a change

- Keep the change to one topic, and match the surrounding code style (the codebase has no linter; read the neighbours).
- Add or update tests: `Tests/VoiceFlowCoreTests` for logic, `Tests/VoiceFlowTests` for app-level behavior.
- Run `scripts/test.sh` and `scripts/build-app.sh` before committing; never commit on a failing build or test.
- Never commit models, audio, `Vendor/`, `build/`, `.build/`, `benchmarks-output/` or secrets (all gitignored).
- If your change can affect recognition or text quality, run the relevant benchmark and put the numbers in the pull
  request and in `docs/ACCURACY.md` or `docs/PERFORMANCE.md` (see `docs/DEVELOPMENT.md` for the commands).
- Update the docs you touched: `docs/ARCHITECTURE.md` for design decisions, `docs/PROGRESS.md` for status.

Commit messages: a short imperative subject (`fix: keep apostrophes in rewrites`), then why the change was needed and
what was measured, wrapped at ~100 characters.

## Benchmarks

Accuracy decisions are made on **recordings of real speech**, not synthetic voices (synthetic audio is used only to
shortlist). The corpora live in `benchmarks/`; recordings stay on your machine. `docs/DEVELOPMENT.md` lists every
benchmark command, and `docs/ACCURACY.md` shows the format results are reported in.

## Reporting bugs and ideas

Use the issue templates. For anything security- or privacy-related, follow [SECURITY.md](SECURITY.md) instead of opening a
public issue.

By contributing you agree that your contributions are licensed under the [MIT License](LICENSE).
