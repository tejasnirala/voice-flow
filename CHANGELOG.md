# Changelog

All notable changes to VoiceFlow. Dates are the dates the work was done on the maintainer's machine.

## 1.0.0 — 2026-09-30

First public version: hold ⌥ (or double-tap for hands-free), speak, and the text is pasted where you were typing. Speech
recognition and text processing run entirely on the Mac.

**Dictation**
- ⌥-key trigger (hold, double-tap for hands-free, Esc cancels) with an ⌥Space fallback; dispatch in ~0.1–1.7 ms
- Speech recognition with whisper.cpp (Whisper medium.en q8_0 + a developer vocabulary prompt, Neural Engine encoder):
  1.1% word error and 97.4% of technical terms on the maintainer's recordings; short dictation pasted in ~0.6–0.9 s
- Long dictations are split at pauses; a guard removes recognizer artifacts
- Clipboard is saved and restored around the paste; text is never lost if pasting fails

**Text modes** — Raw, Clean, Developer, Prompt, Writing, Code. Rules handle fillers, punctuation, spoken symbols
(`package.json`, `--save`, `user_id`), developer corrections (`kubectl`, `nginx.conf`, `useEffect`) and spoken lists.
Apple's on-device model can rewrite Clean/Developer text and powers Prompt and Writing, always behind guards that reject
any change to your words.

**Languages** — English, German, Hindi (Devanagari) and Hinglish, with auto-detection (~0.5 s), a per-app language, and
⌃⇧L to switch. Hindi is transcribed in Devanagari and converted to Hinglish by rules: 5.7% / 3.5% word error on the
maintainer's Hindi recordings.

**App** — menu bar, a window (Home, Modes, Apps, Dictionary, Settings, About), and a draggable pill with live input level
that remembers where you put it. Per-app modes (VS Code → Developer, Slack → Clean, ChatGPT → Prompt, Notes → Writing),
a personal dictionary, Open at Login, and Copy Diagnostics.

**Resource use** — 13 MB and no measurable CPU when idle; the speech model is loaded only while dictating and released
60 s later; no network, no telemetry, nothing written to disk except settings and your dictionary.
