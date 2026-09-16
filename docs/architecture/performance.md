# Performance architecture & measurement methodology

## Instrumentation (in-app, Phase 1+)
`PerformanceMonitor` records spans with `DispatchTime.now().uptimeNanoseconds` (monotonic):

| Span | Start | End |
|---|---|---|
| `hotkey_to_recording` | Carbon hotkey event received | first audio buffer arrives |
| `recording_duration` | first buffer | hotkey release (not latency) |
| `audio_processing_duration` | hotkey release | samples ready for STT |
| `stt_duration` | STT start | transcript returned |
| `llm_duration` | LLM start | text returned (0 in Fast Mode) |
| `text_insertion_duration` | insertion start | ⌘V posted |
| `total_latency` | hotkey release | ⌘V posted |

Spans are also emitted as `os_signpost` intervals for Instruments. Logs hold durations and
character counts only, **never transcript text**. The menu can show the last request's breakdown.

## External measurement (scripts, no sudo)
| Metric | Method |
|---|---|
| Startup time | `open` timestamp → first `applicationDidFinishLaunching` signpost/log line |
| Memory | `footprint <pid>` (phys_footprint, the metric Activity Monitor shows), plus RSS via `ps` |
| CPU | `ps -o %cpu` / `top -l N -pid` sampled over 60 s idle |
| GPU | Per-process `accumulatedGPUTime` from `ioreg -r -c AGXDeviceUserClient` (delta over an interval). No sudo, unlike `powermetrics` |
| Peak RAM (inference) | `getrusage` max RSS in bench harnesses; `footprint` peak in the app |

## Targets (provisional; confirmed from measurements)
| State | Target |
|---|---|
| Idle CPU | 0.0% (no timers, no polling) |
| Idle GPU | 0 GPU time accumulated |
| Idle footprint | < 20 MB (Phase 0 empty shell: 13 MB) |
| Fast Mode overhead (release → text) | < 400 ms for ≤ 10 s utterances |
| Smart Mode overhead | < 1 s for ≤ 10 s utterances |
| After a request | Returns to idle CPU/GPU. Model memory released per the chosen strategy |

## Benchmark discipline
- Record only measured values on this machine, noting date, build, model, backend, input device.
- Report warm and cold separately. "Cold" = first run in a fresh process with shaders already
  compiled. "First-ever" = shader compile included.
