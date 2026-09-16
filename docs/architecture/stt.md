# Speech-to-text architecture

## Candidates evaluated (Phase 0)

| Candidate | Runtime | Status on this machine | Verdict |
|---|---|---|---|
| **whisper.cpp** b5130 | C/C++ (ggml), Metal + Accelerate, prebuilt `whisper.xcframework` (dynamic, 8.5 MB universal) | Linked and benchmarked from Swift | **Primary** |
| Apple SpeechAnalyzer / SpeechTranscriber | OS framework, models managed by the OS | Available. en-US and en-IN installed, hi-IN supported. Benchmarked | **Alternative**, re-test with contextual strings in Phase 4 |
| MLX Whisper | Python + MLX | Not evaluated further | Rejected: Python runtime inside a menu-bar utility |
| WhisperKit | Swift + CoreML | Not evaluated further | Deferred: CoreML model compile/caching plus swift-transformers dependency chain; whisper.cpp already meets latency |
| Parakeet (via whisper.cpp `parakeet.h`) | ggml | Header present in the framework, not tested | Possible Phase 11 experiment (no Hindi) |

## Why whisper.cpp
- In-process C API: no daemon, no IPC, and memory is released with `whisper_free`.
- Prebuilt framework: no CMake, no Xcode. Metal kernels are embedded and compiled at runtime.
- Best technical-vocabulary accuracy in the Phase 0 test (small.en got Next.js, PostgreSQL,
  Redis, and npm run dev correct).
- Supports an initial prompt, a vocabulary-biasing hook for developer terms (Phase 9).
- Multilingual models (`base`, `small`) cover Hindi/Hinglish.

## Integration plan (Phase 4)
- `Vendor/whisper.xcframework` fetched by `scripts/fetch-deps.sh` (SHA-256 pinned), referenced
  as a SwiftPM `binaryTarget`, copied into `VoiceFlow.app/Contents/Frameworks`.
- `SpeechToTextEngine` protocol → `WhisperEngine` actor (serial inference, owns `whisper_context`).
- Input: `[Float]` 16 kHz mono straight from the recorder. No WAV files.
- Params: greedy, `no_timestamps`, `language = en` (or auto for multilingual), 4 threads
  (= performance cores), `use_gpu` and `flash_attn` on.

## Known cost: first Metal load
The first load in a **new binary** took 14.9–15.2 s (runtime Metal shader compilation, measured
twice with two different binaries). Later loads took 0.08–0.34 s. Mitigation options for Phase 6:
1. Accept it (once per install/update).
2. After launch, compile in the background at low QoS. Costs GPU/CPU at startup, against spec §27.
3. Run the very first request on CPU (0.08 s load) while shaders compile.

## Model choice
Undecided until real-voice clips are tested in Phase 4. Current leaning: **base.en** for Fast Mode
latency (0.08–0.26 s), **small.en** if base.en's tech-term errors prove frequent with real
speech. Data: [`benchmarks/stt.md`](../benchmarks/stt.md).
