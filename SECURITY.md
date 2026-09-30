# Security policy

VoiceFlow runs entirely on your Mac: no network calls, no accounts, no telemetry. The security surface is therefore small,
but it does handle microphone audio, the text you dictate and your clipboard.

## Reporting a vulnerability

Please report privately through **GitHub → Security → Report a vulnerability** (private advisory) on
<https://github.com/tejasnirala/voice-flow>, rather than in a public issue.

Useful in a report: what you observed, how to reproduce it, the VoiceFlow version (menu → Copy Diagnostics, or
`VoiceFlow --diagnostics`), and your macOS version. Please don't include recordings or transcripts of anything private.

Expect a first reply within a few days. This is a personal project maintained in spare time, so fixes may take longer.

## What counts as a security issue here

- Audio, transcripts or clipboard contents leaving the machine, or being written to disk when they shouldn't be
- Transcripts or audio appearing in logs (logs are metadata-only by design)
- The clipboard not being restored after a paste
- A rewrite bypassing the guards that keep it from changing your words
- Anything that lets another process trigger dictation, read its text, or run code through VoiceFlow

## Supported versions

The latest commit on `main` is supported. There are no long-term release branches.
