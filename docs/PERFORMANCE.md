# Performance

Measured on this machine only (MacBook Air M4, 16 GB, macOS 27.0; see ARCHITECTURE.md §1). Each result
lists date, build and conditions. Values are only ever copied from tool output, never estimated.

---

## 1. Methodology

### STT harness (`scripts/bench/stt_engines.swift`, driven by `scripts/bench/stt.sh`)
One process per (configuration × audio set/voice). In each process:

| Measurement | How |
|---|---|
| Load | Wall time of model init (`whisper_init_from_file_with_params` / `parakeet_init…` / Apple analyzer setup) |
| First run | Wall time of the first transcription (one-time Metal pipeline creation, buffer allocation, OS model load). Excluded from latency stats |
| Latency | Wall time of `whisper_full` / `parakeet_full` / Apple analyze-and-finalize per clip, warm |
| RTF | latency ÷ audio duration (< 1 = faster than real time) |
| CPU | `getrusage(RUSAGE_SELF)` user+sys delta per clip. All threads of the process |
| GPU | Per-process Metal GPU time delta from the driver's accounting (`ioreg -r -c AGXDeviceUserClient`, `accumulatedGPUTime`). No sudo |
| Memory | `proc_pid_rusage` `ri_phys_footprint` after load and `ri_lifetime_max_phys_footprint` (peak). The same metric Activity Monitor shows |
| Model size | File size on disk |

Caveats:
- Apple SpeechTranscriber runs in a system daemon. Its CPU, GPU/ANE and memory aren't attributable to
  our process, so only latency is comparable.
- Whisper always encodes a 30 s window, so short clips aren't proportionally faster (see §3).
- whisper.cpp threads: 4 (performance cores). Metal with flash attention.

### App-level measurements (from Phase 1)
Startup time, idle footprint, idle CPU (sampled over 60 s), idle GPU time, hotkey→recording latency,
release→text end-to-end latency. The in-app `PerformanceMonitor` uses monotonic-clock spans and
`os_signpost` (no transcript content).

---

## 2. Application shell

### 2.1 Phase 1 shell, 2026-09-17
Release build: status item, menu built on demand, settings load, unified logging. Ad-hoc signed.
`scripts/build-app.sh && scripts/measure-idle.sh [seconds]`.

| Metric | Run 1 (60 s idle) | Run 2 (30 s) | Run 3 (30 s) | Method |
|---|---|---|---|---|
| Launch: kernel process start → `applicationDidFinishLaunching` | **652.6 ms** (first launch after build) | 85.2 ms | 106.3 ms | App's own log line (`kinfo_proc` start time) |
| Idle CPU | 0.00 s (0.000 %) | 0.00 s | 0.00 s | `ps` CPU-time delta over the window |
| Idle wakeups | 2 / 60 s | 4 / 30 s | 5 / 30 s | `top` IDLEW |
| Idle GPU time | 0.000 ms | 0.000 ms | 0.000 ms | ioreg per-process accounting |
| Physical footprint | 13 MB | 13 MB | 13 MB | `footprint` |
| RSS (includes shared frameworks) | 49.8 MB | — | — | `ps` |
| Quit (AppleScript quit → process gone) | 240 ms | 226 ms | 222 ms | script |

Further launches in the same session measured 93.6 ms and 109.4 ms (log). Bundle: 296 KB (executable 288 KB).

**Observations:** the first launch of a freshly built, ad-hoc-signed binary is ~0.65 s (macOS assesses the
new signature on first run); after that ~85–110 ms. Idle cost is effectively zero: no measurable CPU time,
no GPU client, a handful of run-loop wakeups per minute (system/AppKit, no app timers). Settings are read
only at launch and when the menu opens; nothing is written unless the user changes a setting.

### 2.2 Global hotkey (Phase 2), 2026-09-17
Owner test session: real presses of ⌥Space across Safari/Chrome search field, VS Code, Notes, Terminal.
Dispatch latency = `GetCurrentEventTime() − GetEventTime(event)` in the Carbon handler, i.e. from the system's
timestamp on the hotkey event to VoiceFlow's handler. It doesn't include hardware/HID → WindowServer time,
which isn't observable from the app.

| Event | n | min | median | p95 | max |
|---|---|---|---|---|---|
| Press | 26 | 0.09 ms | **0.13 ms** | 0.31 ms | 0.69 ms |
| Release | 26 | 0.08 ms | **0.13 ms** | 0.14 ms | 0.19 ms |

State change to `recording` was logged in the same millisecond as the press in every case.

**Exception, by design:** while VoiceFlow's own status menu is open, macOS holds hotkey events until the menu
closes (observed 2.6–12.6 s). Presses more than 500 ms late are ignored as stale (verified by the owner:
pressing ⌥Space with the menu open does nothing). Idle cost after Phase 2: see §2.3.

**⌥ trigger (event taps), 2026-09-17:** idle with both taps installed: launch 92.9 ms, CPU 0.00 s over 30 s, 6 idle
wakeups, GPU 0, 13 MB. Dispatch latency for ⌥ wasn't measured correctly in the owner test (it compared a nanosecond
event timestamp against `mach_absolute_time` ticks and always read 0). Fixed to use `CLOCK_UPTIME_RAW` nanoseconds;
to be measured in Phase 6.

### 2.3 Idle after Phase 2, 2026-09-17
`scripts/measure-idle.sh 30` with the hotkey registered: launch 88.9 ms, CPU 0.00 s (0.000 %), 1 idle wakeup
in 30 s, GPU 0.000 ms, footprint 13 MB, quit 301 ms. The registered Carbon hotkey adds no measurable idle cost.

### 2.4 Phase 0 shell, 2026-09-16 (for reference)
Empty status item: 13–14 MB footprint, 0.0 % CPU (single `ps` sample), bundle 68 KB.

---

## 3. STT

### 3.1 Synthetic set, Metal / OS, 2026-09-16/17
150 clips per configuration (50 × 3 TTS voices; 1.5–28.3 s). Same runs as ACCURACY.md §5.1.
Load and first run are the worst case over the 3 processes.

| Configuration | Model MB | Load s | First run s | Mean latency s | p95 s | Max s | Mean RTF | CPU s/clip | GPU s/clip | Footprint after load MB | Peak footprint MB |
|---|---|---|---|---|---|---|---|---|---|---|---|
| whisper small.en | 465 | 0.30 | 0.27 | 0.270 | 0.523 | 0.766 | 0.072 | 0.026 | 0.242 | 709 | 728 |
| whisper medium.en q8_0 | 785 | 0.45 | 1.13 | 0.835 | 1.329 | 1.598 | 0.231 | 0.057 | 0.742 | 1132 | 1155 |
| whisper large-v3-turbo (f16) | 1549 | 0.80 | 2.85 | 1.389 | 2.372 | 3.931 | 0.394 | 0.026 | 1.313 | 1827 | 1855 |
| **whisper large-v3-turbo q8_0** | 834 | 0.35 | 1.14 | **1.160** | 2.070 | 2.674 | 0.327 | 0.020 | 1.132 | 1053 | 1073 |
| whisper large-v3-turbo q8_0 + vocab prompt | 834 | 0.44 | 5.74 | 2.636 | 5.664 | 6.665 | 0.751 | 0.033 | 2.374 | 1052 | 1129 |
| whisper distil-large-v3 | 1449 | 0.66 | 1.86 | 1.671 | 2.029 | 2.493 | 0.485 | 0.025 | 1.554 | 1713 | 1753 |
| Parakeet TDT 0.6B v3 q8_0 | 638 | 0.26 | 0.47 | 0.125 | 0.351 | 0.610 | 0.029 | 0.018 | 0.113 | 726 | 762 |
| Apple SpeechTranscriber en-US | OS | 0.00 | 0.36 | 0.106 | 0.252 | 0.419 | 0.026 | n/a | n/a | 3* | 11* |
| Apple SpeechTranscriber en-IN | OS | 0.00 | 0.14 | 0.113 | 0.297 | 0.472 | 0.027 | n/a | n/a | 3* | 11* |

\* In-process only. The model runs in a system daemon whose memory/CPU/ANE use isn't attributed to us.

**Observations**
- **Whisper latency is roughly fixed per clip, not proportional to audio length.** large-v3-turbo q8_0 took
  1.13 s for a 1.5 s clip and 1.33 s for a 28.3 s clip, because whisper.cpp always runs the encoder over a
  full 30 s window. Short dictations pay the whole cost. Parakeet scales with length
  (0.07 s → 0.61 s). Reducing Whisper's encoder window (`audio_ctx`) is a known whisper.cpp option.
  **Phase 6 candidate, allowed only if the human-set accuracy is unchanged.**
- **The vocabulary prompt is expensive:** median 1.62× and up to 6.1× slower per clip (e.g. 1.08 s → 6.59 s),
  with no clear accuracy gain (ACCURACY.md §5.2).
- **q8_0 vs f16 (large-v3-turbo):** 16% lower mean latency, 780 MB less footprint, same accuracy.
- **Metal inference is GPU-bound:** ~0.02 s process CPU time per clip, so the CPU stays nearly idle while
  transcribing.
- **Memory while loaded:** ~1.05 GB for large-v3-turbo q8_0 (model + compute buffers), ~0.73 GB for small.en
  or Parakeet. This drives the cold-vs-warm decision (Phase 6): load takes 0.35 s plus ~1.1 s first run,
  vs ~1 GB kept resident.
- **No 15 s shader compile appeared in these runs** (the harness binary was built before the runs, and the
  macOS shader cache was warm from earlier builds). The v1 exploration measured 14.9–15.2 s for the first
  GPU load in a newly built binary. The app must handle this once per install/update (Phase 6).

### 3.2 CPU vs Metal, 2026-09-17
`scripts/bench/stt.sh cpu-sample`: 5 Rishi clips (3.7 s normal, 3.6 s technical, 3.6 s identifier, 1.7 s
command, 28.3 s natural). Metal numbers are the same clips from §3.1. Per-clip wall time:

| Clip | large-v3-turbo q8_0 **Metal** | large-v3-turbo q8_0 **CPU** | Parakeet **Metal** | Parakeet **CPU** |
|---|---|---|---|---|
| normal-01 (3.7 s) | 1.050 s | 31.383 s (124.2 s CPU time) | 0.087 s | 1.358 s |
| technical-03 (3.6 s) | 1.057 s | 32.058 s | 0.104 s | 1.187 s |
| identifiers-01 (3.6 s) | 1.067 s | 34.656 s | 0.112 s | 1.148 s |
| commands-01 (1.7 s) | 1.084 s | 37.917 s | 0.070 s | 0.530 s |
| natural-01 (28.3 s) | 1.327 s | 44.581 s (176.4 s CPU time) | 0.610 s | 9.126 s |
| Peak footprint | 1073 MB | 1230 MB | 762 MB | 908 MB |

Transcripts were identical between backends (except one Parakeet clip). **CPU inference with this prebuilt
framework is 15–30× slower and saturates ~4 cores, so Metal is required.** The CPU slowness is far beyond
what the thread count alone explains. The prebuilt framework's CPU path may not be optimal; not investigated,
since Metal is available on every target Mac.

### 3.3 Human set (owner's voice, MacBook mic), 2026-09-17
50 clips, 4.9–39.2 s (450 s total; recordings include natural pauses). Same harness and settings.

| Configuration | Model MB | Load s | First run s | Mean latency s | p95 s | Max s | Mean RTF | CPU s/clip | GPU s/clip | Footprint after load MB | Peak MB |
|---|---|---|---|---|---|---|---|---|---|---|---|
| whisper small.en | 465 | 0.38 | 0.29 | 0.267 | 0.499 | 1.034 | 0.032 | 0.024 | 0.246 | 708 | 757 |
| whisper small.en + vocab | 465 | 0.30 | 0.29 | 0.300 | 0.576 | 0.869 | 0.037 | 0.037 | 0.258 | 708 | 786 |
| whisper medium.en q8_0 | 785 | 0.43 | 0.69 | 0.733 | 1.143 | 2.045 | 0.092 | 0.034 | 0.703 | 1131 | 1177 |
| **whisper medium.en q8_0 + vocab** | 785 | 0.46 | 0.80 | **0.837** | **1.318** | 2.281 | 0.106 | 0.059 | 0.736 | 1131 | 1205 |
| whisper large-v3-turbo (f16) | 1549 | 0.78 | 1.02 | 1.103 | 1.311 | 2.539 | 0.143 | 0.030 | 1.031 | 1827 | 1858 |
| whisper large-v3-turbo q8_0 | 834 | 0.41 | 1.21 | 1.277 | 1.450 | 2.816 | 0.166 | 0.025 | 1.234 | 1051 | 1106 |
| **whisper large-v3-turbo q8_0 + vocab** | 834 | 0.33 | 1.47 | **1.418** | **1.596** | 3.002 | 0.186 | 0.032 | 1.362 | 1052 | 1141 |
| whisper distil-large-v3 | 1449 | 0.76 | 1.28 | 1.391 | 1.533 | 2.949 | 0.182 | 0.024 | 1.350 | 1712 | 1753 |
| Parakeet TDT 0.6B v3 q8_0 | 638 | 0.28 | 0.15 | 0.158 | 0.421 | 0.733 | 0.017 | 0.023 | 0.145 | 727 | 773 |
| Apple SpeechTranscriber en-US | OS | 0.00 | 0.36 | 0.118 | 0.280 | 0.449 | 0.014 | n/a | n/a | 3* | 14* |

Notes:
- On real speech the vocabulary prompt costs +11–14% latency for medium.en and large-v3-turbo (synthetic:
  median +62%). Measure again in-app.
- Unlike the synthetic run, f16 large-v3-turbo was faster than q8_0 here (1.10 vs 1.28 s mean). Both
  runs were single passes; run-to-run variance hasn't been measured yet (Phase 6).
- Both finalists are within the latency sanity bound (p95 ≤ 2 s) and use ~1.1–1.2 GB while loaded.

### 3.4 In-app STT (Phase 4), 2026-09-17
Release app, whisper large-v3-turbo q8_0 + developer vocabulary prompt, Metal, residency sets off (below).

**Live dictation path, large-v3-turbo q8_0 + vocab** (`scripts/measure-recording.sh 5 3` with speech played through
the speakers; the model starts loading when recording starts):

| Dictation | Model at release | Press → first audio | Transcribe (5.2 s audio) | **Release → text** | Footprint |
|---|---|---|---|---|---|
| 1 (fresh launch; load 0.35 s during recording) | loaded | 237 ms | 1.106 s | **1119 ms** | 13 → 1110 MB |
| 2 | warm | 169 ms | 1.133 s | **1146 ms** | 1110 MB |
| 3 | warm | 164 ms | 1.105 s | **1114 ms** | 1110 MB |

**Chosen model, medium.en q8_0 + vocab** (same method, 2026-09-17): model load 0.36 s during recording; release → text
**1015 / 914 / 930 ms** (transcribe 0.972 / 0.904 / 0.921 s for 5.2 s of audio); footprint with model loaded 1,185 MB.

An earlier identical run showed the first audio buffer delivered 1976 ms after the press while the model loaded in
parallel, with no audio lost (recording length = press → release). It didn't reproduce in the next run. Watch in Phase 6.

**Release → text is ~1.1 s and dominated by Whisper's fixed 30 s encoder window** (same as §3.1): the main Phase 6 target.

**Model loading and memory:**

| Measurement | Value |
|---|---|
| Model load (shaders cached) | 0.30–0.54 s |
| First model load in a newly built app bundle | 15.5 s (runtime Metal shader compilation, once) |
| SHA-256 verification of the model | Once per file state (record in `models/verified.json`); runs during the first recording |
| Footprint with model loaded | ~1,010–1,110 MB (peak ~1,130 MB) |
| Footprint after unload (`sttUnloadAfterSeconds`) | **141–184 MB**: ~170 MB stays allocated inside whisper.cpp/ggml after `whisper_free` (Malloc Large 133 MB + Small 40 MB; GPU memory < 1 MB). `malloc_zone_pressure_relief` frees 0 MB, so it's live allocations, not caching |
| Bug fixed during measurement | SHA-256 hashing without an autorelease pool kept ~850 MB resident (footprint after load 1,900 MB → 1,057 MB after fix) |

**Long dictations (segmented, ACCURACY.md §5.9):** long-form clips of 66–122 s → 2–3 chunks, 36–67 s of audio sent,
transcribe **2.18–3.52 s** (whole recording before: 2.38–4.92 s, with dropped speech). Owner's live 89.7 s dictation
(before the fix): transcribe 3.13 s.

**Memory growth to watch (Phase 6):** in the owner's session, footprint with the model loaded rose from 1,185 MB to
1,490–1,518 MB after dictating in several apps (including the 89.7 s dictation). Not yet investigated.

**Metal residency sets (decision: off).** With residency sets on (ggml default), ggml starts a thread that wakes
every 5 ms for the process lifetime: **~3,000 idle wakeups per 30 s** measured after unload, from
`ggml_metal_rsets_init` (`ggml-metal-device.m:984–997`). `GGML_METAL_NO_RESIDENCY=1` (set in `main.swift`) prevents
the thread from being created. Thermally controlled A/B (10 owner clips per run, cool-down between runs, alternating):

| Residency sets | Mean latency | p95 | Footprint after load |
|---|---|---|---|
| Off, run 1 / 2 | 1.221 s / 1.180 s | 2.402 s / 2.340 s | 1,012 MB |
| On, run 1 / 2 | 1.219 s / 1.173 s | 2.423 s / 2.305 s | 1,053 MB |

No latency difference and identical transcripts, 41 MB less memory. After unload with residency off: **15–19 wakeups
per 30 s, 0.00 s CPU over 60 s**.

**Thermal caveat:** 50-clip back-to-back runs on this fanless MacBook Air slowed steadily (mean 1.14 → 1.44 → 1.69 →
1.76 → 1.94 s over ~5 consecutive minutes). Benchmark comparisons must alternate variants with cool-downs.

### 3.5 Phase 6 experiment: fitted encoder window (`audio_ctx`), rejected, 2026-09-17
Whisper always encodes a 30 s window, which is the fixed ~0.7 s cost of short dictations. `audio_ctx` shrinks the window
to the audio length (50 frames/s + margin). In-app engine (medium.en q8_0 + vocab), both benchmark sets, variants run
back to back with 45 s cool-downs.

| Variant (margin:min frames) | 50 clips: WER / terms / invented | Long-form: WER / terms | Mean latency, clips ≤ 6 s | 6–12 s | Long-form |
|---|---|---|---|---|---|
| **full window (kept)** | **1.1% / 97.4% / 0** | **0.7% / 97.4%** | 0.725 s | 0.755 s | 2.549 s |
| dynamic 64:500 | 10.2% / 87.2% / 0 | 6.6% / 94.9% | 0.304 s | 0.334 s | 1.999 s |
| dynamic 64:0 | 11.1% / 84.6% / 0 | 6.6% / 94.9% | 0.254 s | 0.376 s | 2.000 s |
| dynamic 128:0 | 25.9% / 65.4% / 0 | 1.8% / 94.9% | 0.276 s | 0.341 s | 2.113 s |

2–3× faster, but every variant fails the approved gate (terms ≥ 95%). Failure mode: **whole transcripts replaced by
"." or "--"** (technical-10, identifiers-04, identifiers-06, architecture-04) and **truncated endings** (natural-01 lost
its last clause). Silently losing a dictation is unacceptable, so the switch was removed.

---

### 3.6 Phase 6: Core ML (Neural Engine) encoder, adopted, 2026-09-17
whisper.cpp runs Whisper's encoder with Core ML when `ggml-medium.en-encoder.mlmodelc` (541 MB, float16) is next to the
model; the prebuilt framework includes Core ML support and falls back to Metal when it's absent. The decoder stays
q8_0 on Metal. In-app engine, variants run with 45 s cool-downs (and a second Metal run beside Core ML):

| | Metal encoder | **Core ML encoder** |
|---|---|---|
| 50 clips: WER / terms / invented | 1.1% / 97.4% / 0 | **1.1% / 97.4% / 0** |
| 50 clips: transcripts identical to Metal | — | **49/50** (files-05: "put" → "Put") |
| Long-form: WER / terms; identical | 0.7% / 97.4% | **0.7% / 97.4%; 7/7** |
| Mean latency, 50 clips | 0.808 s (rerun 0.809 s) | **0.602 s** (−25%) |
| p95 latency, 50 clips | 1.248 s | **1.054 s** |
| Mean latency, long-form | 2.536 s | **2.093 s** (−17%) |
| Footprint after load / peak | 1,091 / 1,188 MB | 1,095 / 1,210 MB |
| Model load | 0.31–0.39 s | 0.30 s; **first load ever 7.4 s** (Neural Engine compile, once per encoder location) |

**Live dictation** (speaker playback, 5.2 s audio): release → text **544–700 ms** (Metal: 914–1,015 ms). After unload:
187 MB footprint, CPU 0.00 s over 30 s, 32 wakeups. **Adopted** (`scripts/fetch-models.sh whisper-coreml medium.en`).

### 3.7 Phase 6: memory growth and decode fallback, 2026-09-17
The owner session and one 10-dictation playback run showed a one-time +292 MB step (1,185 → 1,478 MB) that then stayed
flat. Hypothesis: whisper.cpp's temperature fallback allocating `best_of` = 5 decoders. Tests:
- Benchmark sets with `best_of = 1` and with no temperature fallback: identical transcripts (50/50, 7/7), peak footprint
  ~1,190 MB for all variants, so the fallback never triggered on these clips (no evidence either way).
- 20 further live playback dictations (10 default, 10 `best_of = 1`): flat at 1,182–1,185 MB, **no step reproduced**.
Decision: no decoding change without evidence. Watch for recurrence (the speech log records footprint per dictation).

### 3.8 Phase 6: cold vs warm model, 2026-09-17
Core ML encoder, speaker playback, `sttUnloadAfterSeconds = 0` (model unloaded after every dictation, so each dictation
loads it while recording):

| Recording | Model load (during recording) | Release → text, cold | Warm reference (§3.6) |
|---|---|---|---|
| 5.2 s (×4) | 0.29–0.36 s | **656 / 754 / 706 / 686 ms** | 544–700 ms |
| 1.5 s (×4) | 0.30–0.32 s | **573 / 603 / 573 / 583 ms** | — |

**Cold = warm:** the load finishes before release for any dictation longer than ~0.35 s (shorter ones are discarded as too
short). Keeping the model warm doesn't buy latency.

**Load/unload cycles leak slowly.** Footprint after unload across 20 consecutive cycles (1.5 s dictations):
210, 218, 220, 222, 223, 224, 224, 225, 225, 225, 225, 225, 227, 227, 230, 230, 230, 231, 232, 233 MB
(+23 MB, ~0.7 MB per cycle after the first few), inside whisper.cpp/Core ML.

**Decision:** default `sttUnloadAfterSeconds` 300 → **60 s**. Same latency; ~1 GB is returned a minute after a burst
instead of five; a burst of dictations shares one load, so few leak cycles. Open: the ~190 MB after unload plus the slow
per-cycle growth can only be fully avoided by running STT in a helper process that exits when idle (owner decision).

### 3.9 Phase 6: speech helper process, adopted, 2026-09-17
whisper.cpp moved out of the app into `voiceflow-stt`, a helper started when dictation starts and stopped after
`sttUnloadAfterSeconds` idle (owner chose this over accepting ~190 MB left after in-process unload plus ~0.7 MB growth
per load cycle, §3.8).

| Measurement | Result |
|---|---|
| App footprint: idle / helper running with model loaded / after helper exit | **13 MB / 17–18 MB / 17 MB** |
| Helper footprint with model loaded | 1,180 MB (returned to the system when it exits) |
| App idle after helper exit (30 s) | CPU 0.00 s, 9 wakeups |
| App idle, never dictated (`measure-idle.sh 30`) | launch 113.8 ms, CPU 0.00 s, 5 wakeups, GPU 0, 13 MB |
| Helper launch | 1–5 ms |
| Helper ready (launch + model load), fresh process | **0.33–0.38 s**; 7.2 s once for a newly built binary (Neural Engine compile) |
| Release → text, new helper per dictation (3.1 s audio) | **606 / 639 / 622 / 634 ms** |
| Release → text, warm helper (5.2 s audio) | 581–764 ms |
| App force-killed (`kill -9`) with helper loaded | Helper exits on its own (stdin closed), no orphan |
| Accuracy via `voiceflow-stt --transcribe-benchmark` | Identical transcripts to in-process Core ML: 50/50, 7/7 (WER 1.1% / 0.7%, terms 97.4%) |

The app binary no longer links whisper.cpp; only the helper does. Bundle 5.8 MB (app 1.0 MB, helper 0.7 MB, whisper
framework).

### 3.10 Owner real use after Phase 6, 2026-09-17
Owner dictating paragraphs into VS Code (MacBook mic, helper process, Core ML encoder); transcripts judged accurate by the owner.

| | Hold ⌥ | Hands-free (double-tap) |
|---|---|---|
| ⌥ dispatch latency (event timestamp → handler) | 1.66 ms | 0.22 ms |
| Press → engine running / first audio buffer | 140.9 / 240.6 ms | 80.2 / 184.8 ms |
| Speech helper ready (launched at press) | 0.52 s | already running |
| Audio / speech / sent to model | 40.1 s / 18.3 s / 34.3 s (2 chunks) | 32.4 s / 16.0 s / 26.8 s (1 chunk) |
| Transcribe | 1.553 s | 1.075 s |
| **Release → pasted** | **1,579 ms** (47 words) | **1,087 ms** (54 words) |
| App footprint | 13.0 → 24 MB | 24.5 → 27 MB |

Recording start (≈ 60–140 ms to a running engine, 165–241 ms to the first buffer on the built-in mic) was left as is: the
remaining engine-preparation idea would save only tens of milliseconds.

## 4. Audio recording (Phase 3)

### 4.1 Start latency and cost, 2026-09-17
Release build, MacBook Air Microphone (48 kHz, 1 ch) → AVAudioEngine tap (1024 frames) → AVAudioConverter →
16 kHz mono Float32 in memory. `scripts/measure-recording.sh <seconds> <runs> [--fresh-engine]`: all runs in one
process; "press" = the moment recording was requested (for real hotkey presses: the event timestamp).

| Variant | Run | engine `start()` | Press → engine running | Press → first audio buffer | CPU per 2 s recording |
|---|---|---|---|---|---|
| Reuse engine (chosen) | 1 (cold process) | 128.6 ms | 145.4 ms | 246.0 ms | 40 ms |
| Reuse engine | 2–5 | 66.9–77.3 ms | **68.2–79.2 ms** | **173.0–184.1 ms** | 25–29 ms |
| Fresh engine per recording | 1 (cold process) | 129.1 ms | 146.1 ms | 246.1 ms | 41 ms |
| Fresh engine per recording | 2–5 | 77.5–83.4 ms | 78.3–85.1 ms | 183.3–191.2 ms | 22–28 ms |

Owner hotkey recordings (same session): press → running 96.0 ms, press → first buffer 201.9 ms,
**130 ms of leading digital silence** (the device delivered zeros before real audio), 10.3 s recording
using 69 ms CPU (~0.7 % of one core). The benchmark recordings (`record.sh`, fresh engine per clip) also
start with ~200 ms of zeros; measurement-mode runs above showed 0 ms.

**Owner device test, 2026-09-17 (hotkey, speech):**

| Input device | Press → engine running | Press → first buffer | Leading digital silence | ≈ Real audio starts after press | Recording |
|---|---|---|---|---|---|
| MacBook Air Microphone | 75.5 ms | 179.8 ms | 0 ms | ~0.18 s | 6.1 s, peak −30.6 dBFS, kept |
| AirPods Pro 3 (Bluetooth) | 86.7 ms | 189.4 ms | **342 ms** | **~0.53 s** | 15.0 s, peak −16.4 dBFS, 9.2 s speech, kept; CPU 90 ms; footprint 20.6 → 21.1 MB |

AirPods need a Bluetooth profile switch before the microphone delivers audio, so their first ~0.5 s after the
press is lost. The owner didn't notice a slower start, but words spoken immediately would be clipped.

**What it means:** real audio starts roughly **0.17–0.33 s after the press** (first buffer plus any leading
zeros). Speech that starts at the exact instant of the press can lose its first ~0.2 s. Always-on capture
(pre-roll) would fix that but is ruled out (no continuous microphone). Phase 6 options: show "recording"
only once audio flows, try smaller tap buffers or AUHAL, and measure first-word clipping directly.

**Engine reuse decision:** keeping the stopped AVAudioEngine saves ~10 ms per start. Idle after recording is
the same either way (below), so reuse is on.

### 4.2 Memory and idle after recording, 2026-09-17
| Condition | Footprint | Idle CPU (2 × 30 s windows) | Idle wakeups / 30 s |
|---|---|---|---|
| Never recorded (baseline) | 13 MB | 0.00 s, 0.00 s | 1, 1 |
| After 2 recordings, fresh engine | 14 MB | 0.00 s, 0.01 s | 8, 8 |
| After 2 recordings, engine reused | 14 MB | 0.00 s, 0.01 s | 5, 6 |
| After 5 recordings, engine reused | 14 MB | 0.00 s | 16 (one window) |

During a recording, footprint rises ~2–3 MB (engine + buffers; 16 kHz Float32 = 3.84 MB per minute of audio),
then drops back. After the microphone has been used once, macOS audio services add a few idle wakeups per
30 s (independent of engine reuse), with ~0.01 s CPU per 30 s.

### 4.3 Correctness checks, 2026-09-17
- **End-to-end format:** a sentence played through the MacBook speakers (`say`, Samantha) was recorded
  in-app (debug saving on) as 16 kHz mono and transcribed by whisper large-v3-turbo q8_0 + vocab:
  "The request goes through the reverse proxy before reaching the Express API and redistores the temporary
  session data." One acoustic merge ("Redis stores" → "redistores") over a speaker-to-mic path; the capture
  format and conversion are correct.
- **Max duration:** limit set to 3 s, recording requested for 6 s → stopped at 3.00 s, audio kept.
- **Silence gate:** 12 silent 2 s recordings (room noise, peaks −41…−65 dBFS) → all `silent`; owner tap
  (0.17 s) → `tooShort`; owner speech (10.3 s) → `keep`.

### 4.4 Text insertion (Phase 5), 2026-09-17
Owner session (release build, medium.en q8_0 + vocab), from the `insertion` log:

| Target app | Outcome | Snapshot | ⌘V event | Release → pasted |
|---|---|---|---|---|
| VS Code (first dictation, Accessibility not yet granted) | Left on clipboard, prompt shown | — | — | — |
| VS Code | Pasted, clipboard restored | 1 item, 0.8 ms | 10.7 ms (first) | 860 ms |
| VS Code | Pasted, clipboard restored | 1 item, 0.1 ms | 0.3 ms | 757 ms |
| VS Code → switched to Google Chrome during transcription | Left on clipboard (focus changed) | — | — | — |
| WhatsApp (×4) | Pasted, clipboard restored each time | 1 item, 0.1 ms | 0.3–0.4 ms | 798–1,596 ms |
| VS Code (89.7 s dictation) | Pasted, clipboard restored | 1 item, 0.1 ms | 0.3 ms | 3,133 ms |

Insertion itself costs < 1 ms after the first event; release → pasted is dominated by transcription. The clipboard
is restored 250 ms after ⌘V (no app pasted the old content in these tests).

## 5. LLM (Smart Mode)

### 5.1 Phase 7 benchmark, 2026-09-17
Full results: ACCURACY.md §6. Latency per rewrite (72 entries, warm):

| Candidate | Mean | p95 | Load | Memory |
|---|---|---|---|---|
| **Apple on-device model (chosen)** | **0.79 s** | 2.11 s | warm-up 1.49 s (first use) | system service; VoiceFlow unchanged |
| Qwen2.5-0.5B Q4_K_M (llama.cpp, Metal) | 0.18 s | 0.65 s | 0.83 s | 638 MB |
| Qwen2.5-1.5B Q4_K_M | 0.34 s | 1.35 s | 1.05 s | 1,293 MB |
| Gemma-3-1B Q4_K_M | 0.32 s | 1.07 s | 1.06 s | 934 MB |
| Llama-3.2-1B Q4_K_M | 0.32 s | 1.09 s | 1.06 s | 1,026 MB |
| Qwen2.5-3B Q4_K_M | 0.68 s | 2.79 s | 1.45 s | 2,254 MB |

Rule-based cleanup: effectively 0 ms. Live Smart Mode in the app: rewrite 775–1,181 ms after transcription (model
prewarmed at recording start).

### 5.2 Text modes (Phase 8), 2026-09-17
Rules, per transcript (72 + 22 + 54 entries, release build): Clean 0.02–0.05 ms mean (max 0.4 ms), Developer 0.2–0.4 ms mean
(max 3.1 ms on a 7-dictation long-form transcript). On-device model per rewrite (warm, final prompts): Clean + Smart Rewrite
0.81 s mean / 2.13 s p95; Developer + Smart Rewrite 0.84 / 2.17 s; Prompt 0.98 / 2.65 s; Writing 0.96 / 2.41 s; model warm-up
0.5–1.2 s on first use (prewarmed at recording start in the app). No new timers, threads or idle work; prompt files (a few KB)
load once. App size 6.2 MB. Full results: ACCURACY.md §7.

**Owner live test** (app log, VS Code): release → pasted 1.8–1.9 s (Developer, 8–9 s dictations), 3.9 s (Prompt, 35 s),
4.5 s (Writing, 33 s), 3.0 s and 6.0 s (Clean + Smart Rewrite, 28 s and 65 s). Of that, the model took 1.1–3.4 s; for the
two rejected Clean rewrites (1.8 s and 3.4 s) the time bought nothing. Long dictations are where Smart Rewrite costs most.

### 5.2.1 Developer intelligence (Phase 9), 2026-09-17
Developer mode rules with corrections, per transcript (release build): real transcripts 0.53 ms mean / 3.9 ms max (was 0.40 / 2.9 ms
in Phase 8), spoken forms 0.29 / 1.8 ms. Code mode is the same order. Dictionary: one small JSON read per recording start. No
idle cost; no new threads or timers.

### 5.2.2 Application awareness (Phase 10), 2026-09-17
Per dictation: one `NSWorkspace.frontmostApplication` lookup and, for browsers only, two Accessibility calls (100 ms timeout).
No idle cost: nothing observes app switches.

Owner test (5 dictations, 2026-09-17): detection 0.00 ms (VS Code, WhatsApp, Notes) and 0.10 ms (Chrome, window title read);
all five got the intended mode (Developer, Clean, Prompt via ChatGPT/Claude tab, Writing, Developer). End-to-end release →
pasted 3.1–4.1 s for 22–47 s dictations, of which the on-device rewrite took 1.9–2.6 s; 2 of 5 rewrites were rejected by the
guard (time spent for nothing). The model step dominates latency in model modes → Phase 11.

### 5.3 Phase 0 exploration, 2026-09-16 (for reference)
llama.cpp `llama-bench`, Qwen2.5-1.5B Q4_K_M: Metal pp256 1,033 tok/s, tg64 85 tok/s; CPU 290 / 67 tok/s. A zero-shot
prompt produced a TypeScript code block for a dictated sentence (the first sign of the contract problem in §5.1).

## 6. Open measurements (scheduled)

| Measurement | Phase |
|---|---|
| Hotkey detection latency | 2 |
| First-word clipping (built-in ~0.2 s, AirPods ~0.5 s): measure and mitigate | 6 |
| Cold (unloaded) vs warm strategy; residual ~170 MB after unload (helper process?) | 6 |
| End-to-end release→text latency | 5, 6 |
| Full audit | 11 |
