# VoiceFlow

A local-only macOS menu-bar dictation utility built for software development.

**Hold ⌥ → speak naturally → release → accurate text appears in the focused app.** Double-tap ⌥ for hands-free.
Speech recognition and optional cleanup run entirely on your Mac. No cloud, no telemetry, no stored audio
or transcripts.

> **Status:** 1.0.0, all 13 phases done; final audit passed ([docs/AUDIT.md](docs/AUDIT.md)). Hold ⌥ (or double-tap for hands-free) → speak → text pasted in ~0.6–0.9 s (+0.6–2.6 s in model modes), all on this Mac. Idle: 13 MB, no CPU.
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
- **Code:** for terminals and editors: "git checkout dash b feature slash login" → `git checkout -b feature/login`,
  "const user equals await camel case get user by id open paren id close paren" → `const user = await getUserById(id)`.
  No capitalization or final period. Instant.
- **Developer corrections** (Developer and Code): only with clear context: "kube control get pods" → `kubectl get pods`,
  "in nginx.com" → `nginx.conf`, "use effect hook" → `useEffect hook`, "database_url in the environment" → `DATABASE_URL`.
- **Mode by app** (on by default): VS Code/Cursor/Xcode/terminals → Developer, Slack/Mail/browsers → Clean, ChatGPT/Claude
  (apps or browser tabs) → Prompt, Notes/Notion/Obsidian → Writing. Mode ▸ For <App> sets your own choice per app.
- **Your dictionary** (menu → Open Dictionary File…): `terms` to spell your way and `replacements` ("voice flow" → VoiceFlow).
- **Smart Rewrite** (toggle): also runs the on-device model for Clean and Developer, with a word-for-word guard (+~0.8 s).
  Prompt and Writing use a content-preserving guard: sentences may be restructured, but no content word may be added,
  dropped or replaced.

## App
- **Menu bar:** status, mode, last dictation, Open VoiceFlow…
- **Window** (first launch, ⌘O from the menu, or open VoiceFlow again): Home with setup checklist, Modes, Apps (mode per app),
  Dictionary, Settings, About. Closes back to a menu-bar-only app.
- **Floating pill while dictating:** live microphone level, finish ■ and cancel ✕, then Transcribing / Rewriting / Pasted.
  Drag it anywhere; it reappears where you left it (Settings → Reset Position).

## Languages
English, German, Hindi (Devanagari) and Hinglish. **Auto-detect** is the default: VoiceFlow recognizes which of the three
languages you spoke (0.5 s) and writes it accordingly; ⌃⇧L switches to a fixed language, and the pill shows which one.
Hindi keeps English words in Latin ("इस function में getUserById call करो"); Hinglish is produced from the Devanagari
transcript by rules. Prompt, Writing and Smart Rewrite work in English and German (Apple's on-device model has no Hindi).
Languages other than English need `scripts/install.sh --with-languages` (~4.2 GB of models).

## Install (this Mac)
```sh
scripts/install.sh --with-models   # first time: whisper.cpp framework, speech model (1.4 GB, verified), build, tests, ~/Applications
scripts/install.sh                 # later updates (keeps models, settings, dictionary)
scripts/uninstall.sh [--purge]     # remove the app (--purge also deletes models/settings after asking)
```
Needs only the Command Line Tools. On first use macOS asks for Microphone, Input Monitoring (⌥ trigger) and
Accessibility (paste). Menu bar → **Open at Login** to start with your Mac; **Copy Diagnostics** for troubleshooting
(no transcripts are ever logged).

Everything VoiceFlow stores lives in `~/Library/Application Support/VoiceFlow/`: `models/`, `settings.json`,
`dictionary.json`. Logs go to the macOS unified log (subsystem `local.voiceflow.VoiceFlow`).

## Development
```sh
scripts/fetch-deps.sh && scripts/fetch-models.sh whisper medium.en-q8_0 && scripts/fetch-models.sh whisper-coreml medium.en
scripts/build-app.sh && open build/VoiceFlow.app
scripts/test.sh
```
See [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md), including how to run the accuracy benchmark on your own voice.

## Documentation
| Doc | Contents |
|---|---|
| [`docs/SPEC.md`](docs/SPEC.md) | Requirements (v2) |
| [`docs/PROGRESS.md`](docs/PROGRESS.md) | Phase status, next steps, decision log, session handoff |
| [`docs/AUDIT.md`](docs/AUDIT.md) | Final audit: accuracy, performance, privacy, reliability, UX, known limitations |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Machine, stack, alternatives, STT decision, privacy, dependencies |
| [`docs/ACCURACY.md`](docs/ACCURACY.md) | Benchmark corpus, metrics, threshold, results |
| [`docs/PERFORMANCE.md`](docs/PERFORMANCE.md) | Measurement methodology and results |
| [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md) | Setup, commands, benchmarks, gotchas |
