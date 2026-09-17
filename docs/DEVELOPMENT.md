# Development

## Requirements
- Apple Silicon Mac, macOS 14+ (developed on macOS 27.0, M4, 16 GB).
- Command Line Tools with Swift 6 (`xcode-select --install`). **Xcode isn't required.**
- `python3` (preinstalled) for setup and benchmark scripts only. The app never uses Python.

## First-time setup
```sh
scripts/fetch-deps.sh     # whisper.cpp framework → Vendor/ (SHA-256 pinned)
scripts/fetch-models.sh whisper large-v3-turbo-q8_0     # example; see ACCURACY.md for the chosen model
```
Models go to `~/Library/Application Support/VoiceFlow/models/{whisper,parakeet,llm}/`. Each file is
verified against Hugging Face's SHA-256 before use. Setup is the only step that uses the network.

## Everyday commands
```sh
swift build                    # debug build of all targets
scripts/test.sh                # unit tests (Swift Testing)
scripts/build-app.sh           # release build → build/VoiceFlow.app
open build/VoiceFlow.app       # menu-bar only; look for the mic icon
```
`scripts/test.sh` exists because, with only the Command Line Tools installed, SwiftPM doesn't find the
Swift Testing macro plugin. The script passes its path explicitly.

## Project layout
```
Package.swift                 SwiftPM manifest
Sources/VoiceFlowCore/        Platform-independent logic (unit-tested): accuracy scoring now;
                              state machine, settings, text processing later
Sources/VoiceFlow/            Menu-bar app: AppKit, audio, hotkey, insertion, inference runtimes
Sources/vf-bench/             Benchmark scorer/report CLI
Tests/VoiceFlowCoreTests/     Swift Testing tests
Resources/Info.plist          App bundle metadata (LSUIElement, microphone usage string)
benchmarks/corpus/            Developer-speech accuracy corpus (JSON)
benchmarks/vocabulary.txt     Developer vocabulary used for prompt/contextual-string experiments
scripts/                      build, test, fetch, bench
docs/                         SPEC, PROGRESS, ARCHITECTURE, ACCURACY, PERFORMANCE, DEVELOPMENT
Vendor/                       (gitignored) fetched native frameworks
benchmarks-output/            (gitignored) audio clips, harness binaries, JSONL results, reports
build/, .build/               (gitignored) build output
```

## Accuracy & performance benchmark
```sh
# 1. Models (skip any you don't want to test; missing models are skipped)
scripts/fetch-models.sh whisper small.en medium.en-q8_0 large-v3-turbo large-v3-turbo-q8_0 distil-large-v3
scripts/fetch-models.sh parakeet tdt-0.6b-v3-q8_0

# 2a. Synthetic audio (pipeline validation / shortlisting only)
scripts/bench/make-audio.sh
scripts/bench/stt.sh synthetic

# 2b. Your own voice (the decision set). One folder per microphone.
scripts/bench/record.sh macbook-mic                 # add --include-hinglish to record Hinglish too
scripts/bench/stt.sh human

# Subset of runs: regex filter on run names
scripts/bench/stt.sh human 'large-v3-turbo|parakeet'
```
Reports are written to `benchmarks-output/results/<set>/report.md`: accuracy per category, term recognition,
exact spelling, formatting, latency, RTF, CPU/GPU time, memory, and every erroneous clip with reference vs output.
Copy the decision-relevant tables into `docs/ACCURACY.md` / `docs/PERFORMANCE.md` with date and conditions.

The corpus lives in `benchmarks/corpus/developer-speech.json`. Each entry has `spoken` (what is said),
`reference` (ideal written text) and `terms`. A term can be `canonical|spoken variant`, e.g.
`kubectl get pods|kube control get pods`. Scoring rules are in `Sources/VoiceFlowCore/Speech/Accuracy/` and
explained in `docs/ACCURACY.md`.

## Stable code signing (before Phase 3)
macOS ties Microphone and Accessibility grants to the code signature. Ad-hoc signatures change on every
build, so macOS asks again. Create a self-signed identity once:
1. Keychain Access → Certificate Assistant → **Create a Certificate…**
2. Name `VoiceFlow Dev`, Identity Type **Self Signed Root**, Certificate Type **Code Signing** → Create.
3. `security find-identity -p codesigning` lists `"VoiceFlow Dev"`. It shows `CSSMERR_TP_NOT_TRUSTED`,
   which is expected for self-signed and doesn't matter for local signing. It's absent from the `-v` (valid-only) list.

`scripts/build-app.sh` uses it automatically (override with `VOICEFLOW_SIGN_IDENTITY`). Check with
`codesign -dr - build/VoiceFlow.app`: the designated requirement must be
`identifier "local.voiceflow.VoiceFlow" and certificate leaf = H"…"`, which is stable across rebuilds.
The build doesn't enable the hardened runtime (only needed for notarized distribution; it would need
microphone and library-validation entitlements).

## Known toolchain gotchas
- **No Xcode:** no `xcodebuild`, no offline `metal` compiler. whisper.cpp ships Metal shaders as source,
  compiled at runtime and cached by macOS. The first GPU model load in a *new binary* can take ~15 s.
- **ggml Metal teardown:** always free whisper/parakeet contexts before process exit. Otherwise ggml
  asserts in `ggml_metal_device_free` during static destruction (observed in the benchmark harness).

## Process
Phase status, leftovers and handoff notes: `docs/PROGRESS.md`. After each phase: build → test →
benchmark → verify → review `git diff` → update docs + PROGRESS → commit → **stop for approval**.

## Debugging
- Logs: `/usr/bin/log stream --predicate 'subsystem == "local.voiceflow.VoiceFlow"'`
  (or `log show --last 10m --style compact --predicate …`). **Use the full path in zsh:** zsh's built-in `log`
  command shadows `/usr/bin/log` and fails silently or with "too many arguments".
- Startup & idle measurement: `scripts/build-app.sh && scripts/measure-idle.sh 60`
- Recording measurement (no hotkey needed): `scripts/measure-recording.sh <seconds> <runs> [--fresh-engine] [--stay]`.
  Logs press → engine running / first buffer, leading silence, levels, gate verdict, CPU and footprint.
  Both measurement scripts quit the app; relaunch with `open build/VoiceFlow.app`.
- Save recordings for inspection: add `"saveRecordingsForDebugging": true` to settings.json. WAVs (16 kHz mono)
  go to `~/Library/Application Support/VoiceFlow/debug-recordings/`. Turn it off and delete the folder afterwards.
- Microphone permission: `tccutil reset Microphone local.voiceflow.VoiceFlow` to test the first-run prompt again.
- Settings file: `~/Library/Application Support/VoiceFlow/settings.json` (menu → Open Settings File…). It's
  created only when first changed/opened. An invalid file is moved to `settings.invalid.json` and defaults
  are used (logged as an error).
- Quit: menu → Quit, or `pkill -x VoiceFlow`
- Reset permissions: `tccutil reset Microphone local.voiceflow.VoiceFlow` / `tccutil reset Accessibility local.voiceflow.VoiceFlow`
