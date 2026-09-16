# STT benchmark

## Run 1 — Phase 0 preliminary (2026-09-16)

**Conditions:** MacBook Air M4 / 16 GB / macOS 27.0 · whisper.cpp b5130 prebuilt xcframework ·
greedy decoding, `no_timestamps`, language `en`, 4 threads, flash-attn on Metal ·
Apple SpeechTranscriber (macOS 27.0, en-US) · clips synthesized with macOS `say`
(`scripts/bench/make-audio.sh`), so audio is **cleaner than a real mic** · harnesses in `scripts/bench/`.
Reproduce: `scripts/fetch-deps.sh && scripts/fetch-models.sh whisper tiny.en base.en small.en && scripts/bench/make-audio.sh && scripts/bench/stt.sh`

Clip durations: short 1.84 s · medium 6.81 s · developer 6.51 s · long 28.67 s.

### Latency (seconds, warm model, after one warm-up run; from `scripts/bench/stt.sh`)

| Engine | Model | Backend | Load | Short | Medium | Developer | Long | Peak RSS |
|---|---|---|---|---|---|---|---|---|
| whisper.cpp | tiny.en (75 MB) | Metal | 0.08–0.10* | 0.053 | 0.075 | 0.067 | 0.172 | 249 MB |
| whisper.cpp | tiny.en | CPU | 0.079 | 0.110 | 0.135 | 0.134 | 0.236 | 268 MB |
| whisper.cpp | base.en (142 MB) | Metal | 0.112 | 0.081 | 0.101 | 0.109 | 0.258 | 321 MB |
| whisper.cpp | base.en | CPU | 0.088 | 0.229 | 0.259 | 0.265 | 0.417 | 372 MB |
| whisper.cpp | small.en (466 MB) | Metal | 0.227 | 0.218 | 0.286 | 0.369 | 0.824 | 720 MB |
| whisper.cpp | small.en | CPU | 0.184 | 0.683 | 0.742 | 0.778 | 1.154 | 807 MB |
| Apple SpeechTranscriber | OS-managed | ANE/OS | — | 0.063 | 0.139 | 0.135 | 0.431 | 20 MB in-process† |

\* **First-ever Metal load in a new binary: 14.88 s and 15.23 s** (two binaries). Runtime shader
compilation. Later processes of the same binary: 0.08–0.10 s.
† The model runs in a system process not counted here. Its memory needs separate measurement (Phase 4).
Apple timings include analyzer setup per clip. First run of the process: 0.23–0.35 s.

An earlier ad-hoc run of the same harness (scratch build) agreed within ~10%: e.g. small.en
Metal 0.220 / 0.332 / 0.362 / 0.796 s, base.en Metal 0.075 / 0.102 / 0.109 / 0.263 s.

### Accuracy (same clips)

Reference → what each engine produced (key technical terms only):

| Term spoken | tiny.en | base.en | small.en | Apple en-US |
|---|---|---|---|---|
| Next.js | "next JS" ✗ | "next JS" ✗ | **"Next.js" ✓** (1 run: "next JS") | "next JSAPI" ✗ |
| PostgreSQL | "post-guessql" ✗ | **"Postgresql" ~✓** | **"PostgreSQL" ✓** | "post-GareSQL" ✗ |
| get user by id | "GetUserByE(ed)" ✗ | "getUserByEad" ~ | "getUserByEid" ~ | "get user by eat" ✗ |
| Redis | "Redis" ✓ | "Redis" ✓ | "Redis" ✓ | "radisso" ✗ |
| npm run dev | "npm run they've" ✗ | "npm rundev" ~ | **"NPM run dev" ✓** | "NPM run Dave" ✗ |
| API route | ✓ | "LPI route" (1 of 2 runs) ✗ | ✓ | "JSAPI" ✗ |

"ID" was mis-heard by every engine. The `say` voice pronounces it unusually, so re-test with a real voice.

### Preliminary conclusions (not final — Phase 4 decides)
- Every engine is far below a latency that matters for ≤ 10 s utterances on Metal. **Accuracy
  decides the model, not speed.**
- tiny.en: too many developer-term errors. Likely rejected.
- base.en: fastest acceptable candidate (≈0.1 s for ≤ 7 s clips, 321 MB peak).
- small.en: clearly best on developer vocabulary, ≈0.3 s for ≤ 7 s clips, 720 MB peak.
- Metal is 2–3× faster than CPU at base/small. CPU is competitive only for tiny.
- Apple SpeechTranscriber: excellent footprint, weakest on tech terms without contextual strings.

### Still to measure (Phase 4)
Real-voice clips (built-in mic, AirPods), the spec's full 7-sentence list, multilingual `base`/`small`
with Hinglish, whisper initial-prompt vocabulary biasing, SpeechTranscriber with contextual
strings, daemon memory for SpeechTranscriber, GPU time per request.
