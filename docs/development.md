# Development

## Requirements
- Apple Silicon Mac, macOS 14+ (developed on macOS 27.0, M4).
- Command Line Tools with Swift 6 (`xcode-select --install`). **Xcode isn't required.**

## First-time setup
```sh
scripts/fetch-deps.sh                          # native runtimes → Vendor/ (checksum-verified)
scripts/fetch-models.sh whisper base.en        # models → ~/Library/Application Support/VoiceFlow/models/
```

## Everyday commands
```sh
swift build                                    # debug build of all targets
scripts/test.sh                                # unit tests (Swift Testing)
scripts/build-app.sh                           # release build → build/VoiceFlow.app
open build/VoiceFlow.app                       # run (menu-bar only; look for the mic icon)
```

Why `scripts/test.sh` rather than `swift test`: with only the Command Line Tools installed,
SwiftPM doesn't find the Swift Testing macro plugin (`usr/lib/swift/host/plugins/testing`).
The script passes `-plugin-path` for it.

## Stable code signing (recommended before Phase 3)
macOS ties Microphone and Accessibility grants to the app's code signature. Ad-hoc signatures change
on every build, so macOS asks again. Create a local self-signed identity once:

1. Open **Keychain Access** → Keychain Access menu → **Certificate Assistant** → **Create a Certificate…**
2. Name: `VoiceFlow Dev` · Identity Type: **Self Signed Root** · Certificate Type: **Code Signing** → Create.
3. `security find-identity -v -p codesigning` should list `"VoiceFlow Dev"`.

`scripts/build-app.sh` uses it automatically (override with `VOICEFLOW_SIGN_IDENTITY`).

## Project layout
```
Package.swift            SwiftPM manifest (VoiceFlowCore lib, VoiceFlow exe, tests)
VoiceFlow/               Sources, grouped by responsibility (see docs/architecture/overview.md)
Tests/                   Swift Testing unit tests
Resources/Info.plist     App bundle metadata (LSUIElement, mic usage string)
prompts/                 LLM mode prompts (created in Phase 8)
scripts/                 build, test, fetch, bench
docs/                    SPEC, PROGRESS, architecture, benchmarks, environment, security
Vendor/                  (gitignored) fetched native frameworks
build/, .build/          (gitignored) build output
benchmarks-output/       (gitignored) generated audio and bench binaries
```

## Benchmarks
```sh
scripts/fetch-models.sh whisper tiny.en base.en small.en
scripts/bench/make-audio.sh
scripts/bench/stt.sh
```
Record results in `docs/benchmarks/*.md` with date and conditions. Never write numbers you didn't measure.

## Process
Phases and their status: `docs/PROGRESS.md`. After each phase: build → test → benchmark → verify
→ review diff → update docs + PROGRESS → commit.

## Debugging
- Logs: `log stream --predicate 'subsystem == "local.voiceflow.VoiceFlow"'` (from Phase 1).
- Quit the running app: menu → Quit, or `pkill -x VoiceFlow`.
- Reset permissions: `tccutil reset Microphone local.voiceflow.VoiceFlow`, `tccutil reset Accessibility local.voiceflow.VoiceFlow`.
