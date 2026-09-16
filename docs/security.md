# Security & privacy

VoiceFlow is a local-only utility. This document is the reference for what it can access, what
it stores, and what it never does. Items marked _(planned)_ are designed but not yet implemented.

## Permissions

| Permission | Why | When requested | Without it |
|---|---|---|---|
| **Microphone** (`NSMicrophoneUsageDescription`) | Capture audio while the hotkey is held | First dictation _(Phase 3)_ | Dictation disabled; menu shows how to grant it |
| **Accessibility** | Post the synthetic ⌘V keystroke into the focused app | First insertion; menu shows status _(Phase 5)_ | Text is left on the clipboard with a notice instead of pasted |
| Input Monitoring | **Not required.** The Carbon hotkey API doesn't need it | — | — |
| Speech Recognition | Only if Apple SpeechTranscriber is chosen (Phase 4) | — | — |

Permission grants are tied to the code signature. Ad-hoc signing changes the signature on every
rebuild, so grants may need re-approval. The "VoiceFlow Dev" local identity avoids this (see `development.md`).

## Microphone behavior
- The mic is active **only** between hotkey press and release. The macOS orange indicator
  confirms this.
- No continuous listening, wake word, or background capture.

## Audio & transcript data
- Audio is kept **in memory only** as a Float32 array. It's released as soon as transcription
  finishes. **No audio files are written**, temporary or otherwise.
- Transcripts (raw and processed) exist in memory only until pasted. They're not saved to disk,
  history, or logs.
- Logs record timings, character counts, state transitions, and errors. **Never transcript text
  or audio.**

## Clipboard behavior _(Phase 5)_
- Before inserting, VoiceFlow snapshots **all** pasteboard items and types (text, rich text,
  images, files, custom).
- The transcript is placed on the pasteboard with `org.nspasteboard.TransientType` and
  `org.nspasteboard.ConcealedType`, so well-behaved clipboard managers don't record it.
- After pasting, the original contents are restored, unless the clipboard changed in the meantime
  (e.g. the user copied something). The user's newer content then wins.
- Snapshot data lives in memory for a fraction of a second and is never written to disk.

## Local model files
- Location: `~/Library/Application Support/VoiceFlow/models/{whisper,llm}/`, outside the app bundle.
- Downloaded only by the explicit setup script `scripts/fetch-models.sh` from Hugging Face over HTTPS.
- Native runtimes (`whisper.xcframework`) are fetched at build time with a **pinned SHA-256**.
- _(planned, Phase 12)_ Model files are validated (size/header, plus checksum where published)
  before loading. Invalid or incompatible files are reported, not loaded.
- Model files are data parsed by native C/C++ code (ggml/GGUF parsers). Only use models from
  trusted sources.

## Network behavior
- **Runtime: no network access at all.** No cloud APIs, telemetry, analytics, crash reporting,
  update checks, or remote logging.
- Network is used only by developer/setup scripts (`fetch-deps.sh`, `fetch-models.sh`) that the
  user runs explicitly.
- Verified in Phase 13 with networking disabled (plus a check that the binary has no network
  entitlement or URLSession usage).

## Data retention summary

| Data | Stored? | Where | Lifetime |
|---|---|---|---|
| Audio | No | Memory | Until transcription completes |
| Transcripts | No | Memory | Until paste completes |
| Clipboard snapshot | No | Memory | Until restored (~≤ 1 s) |
| Configuration | Yes | `~/Library/Application Support/VoiceFlow/config.json` | Until deleted |
| Models | Yes | `~/Library/Application Support/VoiceFlow/models/` | Until deleted |
| Logs | Unified log (os_log), no content | System log store | System-managed |

## Non-goals / hard rules
- Never executes commands or shell code derived from speech (spec §43, §45).
- The LLM is a text transformer only: no tools, browsing, or actions.
