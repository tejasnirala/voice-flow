# VoiceFlow — Product & Engineering Spec (v2)

> Condensed from the owner's updated brief (v2, 2026-09-16), which **supersedes v1**. Every requirement
> is preserved; examples are shortened. This file is the contract. Progress is tracked in
> [`PROGRESS.md`](PROGRESS.md). Section numbers match the brief.

## 1. Core product goal
A personal, local-first native macOS dictation utility (inspired by Wispr Flow; not SaaS):
hold a global shortcut (default **⌥ Option + Space**) → speak naturally → release → record locally →
transcribe locally with an **accurate** STT model → optionally clean/transform with a local LLM →
insert into the focused app. Example: "create a next js api route using typescript and postgres" →
`Create a Next.js API route using TypeScript and PostgreSQL.` It must feel like a fast native utility,
not a browser app.

## 2. Non-negotiable priorities (in order)
1. **Transcription accuracy.** Normal English, conversational speech, technical discussion, programming
   terminology, developer vocabulary, framework/database/cloud names, CLI commands, filenames, environment
   variables, identifiers. Reference terms: Next.js, TypeScript, JavaScript, React, Node.js, Express,
   PostgreSQL, MongoDB, Redis, RabbitMQ, Docker, Docker Compose, Kubernetes, AWS, Azure, GCP, JWT, OAuth,
   WebSocket, REST API, GraphQL, middleware, camelCase, snake_case, getUserById, refreshToken, package.json,
   .env, npm run dev, docker compose up, kubectl, git rebase. STT must not routinely turn these into
   everyday words.
2. Then latency. 3. Then resource efficiency. 4. Then features.

**Critical rule:** smaller ≠ better. Choose the smallest/fastest model that **actually meets the required
accuracy**. If a larger model is needed, use it. Optimize performance only after accuracy is established.

## 3. Accuracy benchmarking is mandatory
Before committing to an STT model/runtime, evaluate realistic candidates on this machine (whisper.cpp,
MLX-based Whisper, other mature Apple-Silicon local STT). Measure: accuracy, WER where meaningful,
technical-term accuracy, identifier accuracy, punctuation quality, capitalization quality, transcription
latency, cold start, warm latency, RAM, CPU, GPU, model size, disk footprint. Never fabricate. If WER
can't be measured automatically, document it and use a human-reviewed set.

## 4. Realistic developer speech benchmark
Local suite with categories: normal English ("I need to send an email to the customer tomorrow morning.",
"The meeting has been moved to three o'clock.", "Please review this document before the end of the day."),
technical terminology ("We are using Next.js with TypeScript on the frontend.", "The backend is running on
Node.js and Express.", "The database is PostgreSQL with Redis for caching."), programming identifiers
(getUserById, refreshAccessToken, createInvoice, handleSubmit, isAuthenticated, userSession), developer
commands (npm run dev, npm install, git rebase main, docker compose up/down, kubectl get pods), files and
config (package.json, tsconfig.json, docker-compose.yml, .env, .env.local, nginx.conf), architecture
discussion ("The request goes through the reverse proxy before reaching the Express API.", "The access
token expires after fifteen minutes and the refresh token lasts for one day.", "Redis stores the temporary
session data."), longer natural speech, optional English/Hindi/Hinglish. Don't add multilingual support
at the expense of English/developer accuracy unless benchmarks show it's viable.

## 5. The LLM must not hide bad STT
If STT says "react router" when the user said "Redis router", the LLM must not guess from context.
Uncertain identifiers must not be silently invented. Pipeline: speech → accurate STT → conservative
transcript → optional transformation. The LLM does punctuation, capitalization, formatting, filler removal,
sentence structure, spoken-command readability, and term preservation. It preserves uncertain content
rather than inventing.

## 6. Local only
No runtime network requirement. No cloud speech APIs (OpenAI, Google, Azure…), remote transcription,
remote LLMs, telemetry, analytics, tracking, background network calls, or uploading audio or transcripts.
Temporary recordings are deleted after processing unless explicitly retained for debugging/benchmarking.
Works offline.

## 7. Dependencies
Personal app, not published. Evaluate mature local runtimes pragmatically. Every dependency needs a clear
reason. Prefer native macOS APIs, Apple frameworks, lightweight native libraries, efficient local inference.
Avoid bloat.

## 8. Native architecture
No Electron, React wrappers, browser architecture, local web server as the primary architecture, or
Python desktop runtime. Prefer Swift, SwiftUI, AppKit, native APIs. C++/Rust only with demonstrated
performance benefit (inference/audio).

## 9. Lightweight
Low idle RAM (not hundreds of MB idle), near-zero idle CPU/GPU, fast startup and hotkey response, minimal
background activity, disk footprint and dependencies. Don't keep large models loaded unnecessarily.
Consider lazy loading, unloading, warm vs cold, mmap, quantization, efficient inference and buffers.
But never sacrifice accuracy for footprint. Decide from measurements.

## 10. Fast UX
IDLE → hotkey pressed → RECORDING → released → TRANSCRIBING → OPTIONAL PROCESSING → INSERTING → IDLE.
Avoid polling, unnecessary workers/IPC/serialization/process spawning, loading the LLM per transcription,
and loading models at startup unless benchmarks justify it. Measure latency; never claim "instant"
without measurement.

## 11. Two modes
**Fast Mode:** audio → STT → paste (no LLM, lowest latency). **Smart Mode:** audio → STT → local LLM →
paste (grammar, punctuation, fillers, readability, technical formatting, term preservation). Fast Mode
stays available.

## 12. Local LLM
Secondary to STT. Evaluate MLX, llama.cpp, or another native local runtime on this machine; don't assume.
Model: local, quantized where appropriate, small, fast, memory-conscious, deterministic/conservative.
A text transformation engine, not a chatbot. It doesn't answer questions, browse, execute commands,
invent information, needlessly rewrite identifiers, or change meaning.

## 13. Developer-aware transcription
Optional local developer vocabulary/lexicon (frameworks, languages, libraries, databases, cloud,
CLI commands, identifiers, file names, env vars, architecture terms). Must be **conservative**: no global
replacement of words that merely resemble technical terms. Context matters.

## 14. Text insertion
Clipboard + ⌘V. Preserve existing clipboard as reliably as practical (save → set → paste → restore).
Never permanently overwrite it. Handle paste failures gracefully.

## 15. Global hotkey
Default ⌥Space; press-and-hold records, release stops. Configurable later. Handle key-down, key-up,
cancellation, duplicate events, permission failures, application focus changes.

## 16. Permissions
Microphone, Accessibility, Input Monitoring where required. Explain why each is needed. Never fail
silently; give useful error messages.

## 17. UI
Minimal menu-bar utility. States: Idle, Recording, Transcribing, Processing, Error. Clear recording
feedback (e.g. "🎙 Recording…"). An optional lightweight floating indicator. No large settings-heavy UI.

## 18. State machine
Explicit: IDLE, RECORDING, TRANSCRIBING, PROCESSING, INSERTING, ERROR. Explicit transitions
(IDLE →hotkey→ RECORDING →release→ TRANSCRIBING →STT ok→ PROCESSING →ok→ INSERTING →paste ok→ IDLE).
Failures return to a safe state.

## 19. Reliability
No crash when: microphone fails, transcription fails, model load fails, LLM fails, paste fails,
Accessibility is missing, user cancels, active app changes, model files are missing, memory is short.
If Smart Mode fails, fall back to the STT result. **Never silently lose user speech.**

## 20. Model storage
Large models are not in the app bundle. Separate application, models, configuration, temporary audio,
logs. Models live in a user-local app directory. Detect installed / missing / incompatible / corrupted.
No automatic runtime downloads unless the user explicitly chooses that.

## 21. Performance benchmarking
STT: model, size, audio duration, latency, real-time factor, RAM, CPU, GPU, accuracy, technical-term
accuracy. LLM: model, size, input/output tokens, latency, RAM, CPU, GPU. App: startup time, idle RAM/CPU,
recording start latency, STT latency, LLM latency, end-to-end latency. Measure first, then optimize.

## 22. Cold vs warm model
Compare cold (record → load → transcribe → unload) vs warm (model kept available) on latency, RAM,
CPU, GPU, battery. Choose by measurement. Keeping STT warm is acceptable if the latency benefit is
significant and memory reasonable.

## 23. Decision rule (never reverse)
1. Accurate enough? No → better model. Yes → 2. Improve latency (inference/runtime) → 3. Reduce RAM
(loading/quantization) → 4. Expand features. Never "tiny is faster, so use it"; ask "which model gives
acceptable accuracy with reasonable latency/resources?"

## 24. Project structure
Modular. Suggested: App (AppDelegate, MenuBar, ApplicationState), Audio (AudioRecorder, AudioSession,
AudioBuffer), Hotkey (GlobalHotkeyManager), Speech (SpeechEngine, STTModelManager, TranscriptionResult,
AccuracyBenchmark), Processing (TextProcessor, LocalLLMEngine, PromptProcessor, DeveloperVocabulary),
Insertion (ClipboardManager, TextInserter), Permissions (PermissionManager), Settings (SettingsManager),
Diagnostics (Logger, PerformanceMonitor), Tests. May be changed if implementation suggests better.

## 25. Methodology (every phase)
1 Inspect project · 2 Explain the plan · 3 Implement only that phase · 4 Build · 5 Run tests ·
6 Run relevant benchmarks · 7 Fix problems · 8 Review · 9 Check CPU/RAM/performance implications ·
10 Update docs · 11 Show what changed · 12 Only then move on. **Stop for owner approval at phase ends.**

## 26–39. Phases
- **0 Machine & architecture discovery:** inspect machine/tools/frameworks; evaluate STT, LLM, model
  loading, audio, hotkey, Accessibility, clipboard options; several STT candidates; benchmark strategy
  and initial harness; `docs/ARCHITECTURE.md` with Machine (CPU, GPU, RAM, macOS, architecture, Swift,
  Xcode), Proposed stack (UI, audio, hotkey, STT runtime/model, LLM runtime/model, insertion, storage,
  testing), Alternatives considered per component (option, advantages, disadvantages, performance,
  memory, integration complexity, decision), STT decision (models evaluated, why, which to benchmark,
  accuracy threshold, performance measurements). No fabricated results. **Stop for approval.**
- **1 Native macOS shell:** menu bar, minimal UI, lifecycle, logging, settings foundation, buildable.
  No STT. Validate build, launch, quit, menu bar, memory, CPU.
- **2 Global hotkey:** ⌥Space key-down/up, cancellation, permission handling, state transitions,
  extensive tests.
- **3 Audio recording:** native APIs, correct sample format for the STT runtime, no unnecessary
  resampling, temp storage or memory buffer, automatic cleanup, duration limits, cancellation.
  Validate quality, memory, CPU, recording latency.
- **4 STT integration:** local inference, no network, model manager, error handling, benchmark
  instrumentation. Run the accuracy benchmark (normal, technical, developer, identifiers, commands,
  long, natural). **Don't proceed until STT quality is acceptable**; evaluate a better model if not.
- **5 Text insertion:** clipboard + ⌘V, tested in VS Code, Terminal, browser, Slack, Discord, Notes,
  text editors. Clipboard restoration. First usable end-to-end product.
- **6 Fast path optimization:** recording, STT, insertion. Measure end-to-end, STT, RAM, CPU, GPU.
  Optimize by measurement only (warm-up, mmap, threading, buffering, loading, inference config,
  quantization, allocations, process boundaries). Never reduce quality to improve benchmarks.
- **7 Local LLM:** optional Smart Mode, conservative, prompts for cleanup, punctuation, grammar,
  term preservation, developer formatting. Transforms, never answers.
- **8 Text modes:** Raw, Clean, Developer, Prompt, Writing. All preserve meaning.
- **9 Developer intelligence:** terms, identifiers, commands, filenames, URLs, code terminology.
  Dictionary, protected terms, conservative correction, context-aware formatting, code mode. No
  overcorrection.
- **10 Application awareness:** detect the active app; configurable per-app defaults (VS Code →
  Developer, Terminal → Raw/Developer, Slack → Clean, Browser → Clean, ChatGPT → Prompt, Notes → Writing).
- **11 Final performance optimization:** audit idle RAM/CPU/GPU, startup, hotkey latency, recording
  start latency, STT, LLM, end-to-end, model memory, disk. Optimize where justified.
- **12 Packaging:** proper app bundle, clean config, model discovery, settings persistence, permission
  handling, logging, crash/error handling, easy local install. No unnecessary installers or services.
- **13 Final audit:** accuracy (reliable STT, terms, identifiers, punctuation), performance (idle CPU/RAM,
  startup, transcription speed), privacy (audio/text never leave, no network, no telemetry), reliability
  (STT fail, model missing, permission denied, paste fail, LLM fail), UX (recording feedback, hotkey
  reliability, unobtrusive).

## 40. Engineering rules
1 Don't over-engineer. 2 No unjustified dependencies. 3 No cloud functionality. 4 Don't sacrifice
accuracy for speed. 5 Don't sacrifice speed unnecessarily for features. 6 Measure before optimizing.
7 Never fabricate benchmark results. 8 Never hide poor STT behind an LLM. 9 Never silently hallucinate
technical terms. 10 Prefer native macOS APIs. 11 Keep large models out of the bundle. 12 No permanent
background CPU/GPU activity. 13 No permanent audio storage by default. 14 No data to external services.
15 Keep the STT model/runtime replaceable.

## 41. Git
After each phase: `git status`, `git diff`, review, one meaningful commit (e.g. `feat: add global hotkey
recording trigger`). No unrelated changes in a commit.

## 42. Documentation
Maintain `README.md`, `docs/ARCHITECTURE.md`, `docs/PERFORMANCE.md`, `docs/ACCURACY.md`,
`docs/DEVELOPMENT.md`. Explain: why this STT runtime, STT model, LLM runtime, LLM model, architecture,
model loading strategy, and the measured performance characteristics.

## 43. Final product
A tiny native menu-bar utility with extremely accurate local STT, fast global hotkey, optional local AI
cleanup, developer-aware vocabulary, reliable insertion, minimal resources, no cloud, no telemetry, no
unnecessary background processes. Hold → speak naturally → release → wait briefly → accurate text appears.
The user shouldn't need to think about models or infrastructure.

## 44. Guiding statement
Accuracy first, then latency, then resource efficiency, then features. A fast inaccurate app is not
acceptable. A slightly larger app with consistently reliable transcription beats a tiny one that often
gets words wrong.

## Addenda (owner requests)
- Track phases (completed, next, leftovers, handoff) in `docs/PROGRESS.md` so any new session has full context.
- Build with SwiftPM + a script-assembled .app; Xcode not required (owner's choice, 2026-09-16).
