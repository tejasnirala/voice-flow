# Local LLM architecture

The LLM is **optional**. Fast Mode (default) never loads it. It's used only when Smart Processing
is on, and only for modes that need it.

## Runtime evaluation (Phase 0)

| Runtime | Integration | Evaluation | Verdict |
|---|---|---|---|
| **llama.cpp** b11005 | In-process C API. Prebuilt `llama.xcframework` (zip 57.8 MB, all platforms) or macOS dylibs | Benchmarked via release binaries: Qwen2.5-1.5B Q4_K_M, Metal pp 1033 t/s, tg 85 t/s | **Chosen** |
| Ollama | Separate daemon, localhost HTTP | Not installed. Rejected by design | Rejected: spec §43 forbids a localhost server; a permanent daemon costs idle RAM |
| MLX (mlx-swift 0.31.6) | Swift package | Can't build from source without Xcode (Metal toolchain). Prebuilt `Cmlx.xcframework` zip is 202 MB | Rejected for now: binary weight and toolchain. Revisit only if Xcode is ever installed and llama.cpp is too slow |

## Model candidates
Starting point: **Qwen2.5-1.5B-Instruct Q4_K_M** (1.04 GiB). Phase 7 compares:
Qwen2.5-0.5B-Instruct Q4_K_M (0.49 GB), Gemma 3 1B IT Q4_K_M (0.81 GB), Llama 3.2 1B Instruct
Q4_K_M (0.81 GB).

## Behavioral findings (Phase 0)
- **Zero-shot prompt fails the spec.** "create a function called get user by id…" produced a
  TypeScript code block. The model *answered* instead of transforming.
- **Few-shot prompt works.** Same input →
  `Create a function called getUserById that accepts a string id and returns a promise of user or null.`
  It didn't convert "promise of user or null" to `Promise<User | null>`, so Phase 9 needs more work.

## Design rules (for Phase 7–9)
1. Rule-based first: filler removal, spacing, and known-term casing (a vocabulary map:
   "postgres q l" → PostgreSQL) run without any LLM. The LLM handles only what rules can't.
2. Fixed system prompt + few-shot examples per mode (`prompts/*.txt`), temperature 0, capped
   `n_predict` (≈ 1.5× input tokens + margin).
3. **Output guard:** reject LLM output and fall back to the rule-based text if it contains code
   fences, is much longer or shorter than the input, or starts answering ("Sure", "Here").
4. **Prefix KV-cache reuse:** evaluate the fixed system + few-shot prefix once per model load.
   Per-request prompt evaluation then covers only the transcript (saves ~150–200 ms measured).
5. Lazy load on first Smart request, unload after an idle timeout (value decided in Phase 11).

## Open technical risk
whisper.xcframework and llama.xcframework both contain their own ggml. As separate dynamic
frameworks, two-level namespaces keep their symbols apart, but each creates its own Metal
device, pipelines, and shader compile. Phase 7 checks: (a) both frameworks side by side,
(b) the llama.cpp ggml dylibs shared with a whisper build from source (needs CMake via Homebrew).
Pick the lighter one by measurement.
