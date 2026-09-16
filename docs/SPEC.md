# VoiceFlow — Product & Engineering Spec

> Condensed from the original project brief (2026-09-16). Every requirement from the brief
> is preserved here; long ASCII diagrams and repeated examples were shortened. When in doubt,
> this file is the contract. Progress against it is tracked in [`PROGRESS.md`](PROGRESS.md).

## 1. Objective
A personal, lightweight, ultra-low-latency, 100% offline macOS voice-dictation utility for
the owner's development workflow. Inspired by Wispr Flow's workflow — **not a clone**.

Flow: hold global hotkey (default **⌥ Option + Space**) → speak → release → local STT →
optional local text processing → paste into the focused app.

Example: "create a function called get user by id which accepts a string id and returns a
promise of user or null" → `Create a function called getUserById that accepts a string id and returns a Promise<User | null>.`

## 2. Priorities (in order)
1. Speed / latency 2. Lightweight resource usage 3. Offline privacy 4. Reliability
5. Transcription quality 6. Developer-oriented intelligence 7. UI 8. Feature breadth

Never add a feature that materially increases RAM, CPU, GPU, startup time, latency, binary
size, or background consumption without clear benefit.

## 3. Performance philosophy
Runs all day. Idle: ~0% CPU, ~0% GPU, minimal RAM. No polling loops, unnecessary timers,
busy waiting, continuous mic processing, background threads, continuous inference, or
unnecessary filesystem activity. Event-driven architecture.

## 4. Latency is first-class
Release → very short delay → text. Measure, don't claim. Instrument:
`recording_duration, audio_processing_duration, stt_duration, llm_duration,
text_insertion_duration, total_latency`. Recording duration is not latency.

## 5. Do not over-engineer
No microservices, backend, REST API, database, cloud, Docker/K8s, auth, accounts, web
frontend, Electron, unnecessary networking, or abstraction layers. Native executable +
local model runtime + local model files.

## 6. Native technology
Evaluate Swift / Objective-C / Rust / C++ on performance, binary size, macOS API integration,
hotkeys, mic, Accessibility, clipboard, concurrency, maintainability, AI runtime integration.
Default expectation Swift + AppKit/SwiftUI (validate). A small C/C++/Rust module only with a
measurable or important advantage.

## 7. Architecture
Menu bar app → Global Hotkey Manager → Audio Recorder (AVAudioEngine) → Local STT (Whisper)
→ Transcript Processor (optional local LLM) → Text Insertion (clipboard + paste) → current app.

## 8. Lightweight app
Models are external resources in `~/Library/Application Support/VoiceFlow/models/`
(`whisper/`, `llm/`), never embedded in the bundle.

## 9. Model memory strategy
Don't load multiple large models simultaneously. Ideal: idle = nothing loaded; recording =
audio only; STT = Whisper; processing = LLM only if required; release when appropriate.
Benchmark **A** unload after every request / **B** keep Whisper warm, unload LLM /
**C** keep both warm — measure latency, RAM, CPU, GPU, choose from data.

## 10–11. Speech-to-text
Evaluate whisper.cpp, MLX Whisper, other mature Apple-Silicon Whisper implementations. Must be
local, offline, Apple Silicon, accurate, low latency, reasonable memory, strong English,
ideally Hindi/Hinglish, technical vocabulary. Benchmark tiny/base/small; pick the **smallest
sufficiently accurate** model (accuracy, latency, RAM, GPU, startup, Apple Silicon perf).
Benchmark script/utility required; test sentences include:
- Create a Next.js middleware for authentication.
- Create a function called getUserById.
- Run npm install and then npm run dev.
- Create a PostgreSQL index on the email column.
- Use Redis for caching the API response.
- The refresh token expires after one day.
- Open the authentication middleware.

Document in `docs/benchmarks/stt.md`.

## 12–15. Local LLM
Not required for basic dictation. **Fast Mode** (default, lowest latency): audio → Whisper →
paste. **Smart Mode**: audio → Whisper → local LLM → paste. User chooses.
Small and fast over large; narrow job: transcript → clean/format/preserve intent → text.
Prioritize latency, memory, determinism, instruction following, technical vocabulary.
Runtimes to evaluate: MLX, llama.cpp, Ollama — by startup latency, warm latency, RAM, GPU, CPU,
Apple Silicon acceleration, integration complexity, model availability, offline. Prefer native
in-process integration over a permanently running daemon unless benchmarks justify it.

## 16. Processing modes
Raw (minimal), Clean (remove fillers, punctuation), Developer (technical formatting),
Prompt (spoken thoughts → clean AI prompt), Writing (polished prose).
Text-processing modes, never autonomous agents.

## 17. Strict LLM behavior
Must NOT answer questions, invent information, add explanations, change technical meaning,
hallucinate APIs, create facts, execute commands, browse, or call tools. It TRANSFORMS text.

## 18. Developer mode
Understands camelCase, PascalCase, snake_case, kebab-case; JavaScript, TypeScript, React,
Next.js, Node.js, Python, Java, SQL; PostgreSQL, MongoDB, Redis, RabbitMQ; Docker, Kubernetes;
AWS, Azure, GCP; npm, pnpm, yarn, git, docker, kubectl; HTTP, REST, JWT, OAuth, API, JSON.
Preserves identifiers, filenames, paths, commands, URLs, package names, API names.
"get user by id" → `getUserById` (not "get user by ID") in Developer mode.

## 19. Global hotkey
Default ⌥Space. Key down → start recording immediately; held → record; key up → stop →
process → paste. Works while other apps are active. Native events, no polling.

## 20. Audio
Native APIs (AVAudioEngine or better, per evaluation). Mic permission, low-latency capture,
correct sample rate, minimal conversion, in-memory buffering, minimal disk I/O, no unnecessary
audio files. Recording only while actively dictating.

## 21. Silence handling
Empty / extremely short / silent recording → do nothing; no LLM, no expensive processing.

## 22. Text insertion
Save clipboard → set text → ⌘V → restore clipboard. Preserve all representations (text,
images, rich content, others) where feasible. Abstraction: `TextInsertionService`.

## 23. Application context
`ActiveApplicationProvider`: app name + bundle identifier. Later: Cursor/VS Code/Terminal →
Developer, ChatGPT → Prompt, Slack → Writing. No complicated automation initially.

## 24. Menu bar UI
Extremely lightweight menu-bar utility:
```
VoiceFlow
──────────────
● Ready
Mode ▸ Developer / Clean / Prompt / Writing / Raw
Smart Processing ▸ ✓ Enabled
Settings
Quit
```
No dashboard, animations, heavy rendering, React, webview, or continuous visual effects.

## 25. State machine
IDLE → RECORDING → TRANSCRIBING → PROCESSING → INSERTING → IDLE.
ANY → ERROR → IDLE. ANY ACTIVE → CANCELLED → IDLE. Deterministic transitions.

## 26. Concurrency
Native/structured concurrency. No excessive threads, thread-per-request, busy waiting,
unnecessary queues, or UI blocking. Menu stays responsive during STT/LLM.

## 27. Startup
Do: load config, init menu bar, register hotkey, prepare lightweight services.
Don't: load Whisper/LLM, init GPU inference, scan large files. Lazy initialization.

## 28–29. Memory & GPU targets
Set practical targets after benchmarking. Idle very low; recording small increment; STT only
required model; LLM only when Smart Processing enabled. Use smaller/quantized models under
memory pressure. GPU ≈0% idle; use GPU during inference only when it reduces latency enough
to justify it — benchmark CPU vs Metal.

## 30–31. Network & privacy
Works with Wi-Fi off / no internet. No cloud APIs, telemetry, analytics, remote logging,
remote inference/transcription. Do not persist recordings, raw or processed transcripts.
Temporary audio deleted after processing. Logs contain no transcript content by default.

## 32. Security doc
`docs/security.md`: microphone and accessibility permissions, clipboard behavior, temp files,
local model files, network behavior, data retention.

## 33–34. Benchmarks (required, never fabricated)
`docs/benchmarks/`: `stt.md`, `llm.md`, `startup.md`, `memory.md`, `latency.md`. Record startup
time, idle RAM/CPU/GPU, recording overhead, STT latency, LLM latency, end-to-end latency, peak
RAM/CPU/GPU. Only values measured on this machine.
Test cases: **Short** "Hello, this is a test." · **Medium** "Create a Next.js API route that
validates the request body and stores the user in PostgreSQL." · **Developer** "Create a
function called getUserById that accepts a string ID and returns a Promise of User or null."
· **Long** natural 20–30 s developer explanation.

## 35. Dependencies
Minimal; each must answer "why do we need this?". Prefer Apple frameworks, system APIs, small
native libraries. Document in `docs/dependencies.md`.

## 36. Model downloads
May download during setup; runtime never needs network. Models in
`~/Library/Application Support/VoiceFlow/models/{whisper,llm}`. Detect missing / valid /
invalid / incompatible.

## 37. Project structure
`VoiceFlow/{App,Core,Audio,Speech,Intelligence,Input,Permissions,Configuration,ApplicationContext,UI}`,
`Tests/`, `prompts/{clean,developer,prompt,writing}.txt`, `scripts/`,
`docs/{architecture/,benchmarks/,environment.md,security.md,dependencies.md,development.md}`,
`README.md`, `.gitignore`. Adjust if architecture requires.

## 38. Abstractions
Boundaries: AudioRecorder, SpeechToTextEngine, TranscriptProcessor, TextInsertionService,
ActiveApplicationProvider, HotkeyManager, ModelManager, PerformanceMonitor. No excessive
interfaces — only at hardware, native-library, and model boundaries.

## 39. Testing
Unit: state machine, mode selection, prompt loading, configuration, clipboard preservation,
transcript processing, error handling. Integration: audio→STT, STT→processor,
processor→insertion. Mocks where hardware/models unavailable.

## 40. Git
Meaningful conventional commits (`chore: initialize project`, `feat: add global hotkey`, …).
Never commit models, recordings, secrets, build artifacts, temp data.

## 41. Phases
0 Machine & architecture discovery (docs + initial project that builds) · 1 Lightweight native
shell (menu bar, config, state machine, permissions; measure startup/idle RAM/CPU/GPU) ·
2 Global hotkey (measure detection latency) · 3 Audio (measure recording startup latency,
memory) · 4 Local STT (benchmark sizes, choose smallest acceptable) · 5 Text insertion —
**core product must work end-to-end offline** · 6 Performance pass (audio startup, model init,
STT, memory, concurrency, insertion; don't continue until the fast path feels good) ·
7 Local LLM (Smart Processing only; cold/warm, RAM, CPU, GPU) · 8 Processing modes ·
9 Developer optimization (+ tests for identifiers, paths, commands, frameworks, DBs, APIs) ·
10 Application awareness (per-app mode defaults) · 11 Perf round 2 (warm vs cold, loaded vs
unloaded, CPU vs Metal, small vs larger, LLM on vs off) · 12 Packaging (release build, bundle,
icon, versioning, model setup, launch at login, install docs) · 13 Final offline audit.

## 42. Development rule (after EVERY phase)
1 Build · 2 Run tests · 3 Run relevant benchmark · 4 Verify functionality · 5 Inspect git diff ·
6 Update documentation · 7 Fix issues · 8 Commit · 9 Only then continue. Never stack
unverified phases.

## 43. Never
Electron; React desktop UI; localhost server; cloud APIs; remote LLMs; unnecessarily large
models; continuously running mic; polling keyboard or app state; persisting transcripts or
audio; analytics/telemetry; unnecessary dependencies; building an agent; arbitrary shell
execution; prioritizing features over latency.

## 44. Future (do NOT implement now)
Voice commands, voice editing, context-aware prompts, custom vocabulary, streaming
transcription/insertion, voice macros, per-app intelligence, local command execution.

## 45. Future command execution safety
Voice → interpretation → visible preview → explicit confirmation → execution. Never execute
solely because something was spoken.

## 46. Product feel
"A tiny macOS utility that quietly sits in the menu bar and turns my voice into text almost
instantly" — not "a giant AI application running in the background."

## 47. Final acceptance test
1. Start VoiceFlow → lightweight menu-bar app. 2. Internet disconnected. 3. Open Cursor, focus a
text field. 4. Hold ⌥Space, say "create a function called get user by id that accepts a string
id and returns a promise of user or null", release. 5. Local STT → Developer mode →
inserted `Create a function called getUserById that accepts a string id and returns a Promise<User | null>.`
6. Clipboard preserved. 7. No data leaves the machine. 8. CPU/GPU return near idle; memory
reasonable. 9. Repeat in Terminal, VS Code, Browser, ChatGPT, Claude.

## 48. Guiding principle
**Use the minimum amount of computation necessary to produce the desired result.** No LLM if
not needed; native API over library; smaller model if sufficient; lazy-load; don't run what
needn't run; don't store what needn't be stored; don't add unnecessary dependencies.

## Addendum (2026-09-16, owner request)
Track phases (completed, next, leftovers) in `docs/PROGRESS.md` so any new session has full
context. Build tooling: SwiftPM + script-assembled .app; do not require Xcode.
