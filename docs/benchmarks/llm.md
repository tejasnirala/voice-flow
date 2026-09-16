# LLM benchmark

## Run 1 — Phase 0 preliminary (2026-09-16)

**Conditions:** MacBook Air M4 / 16 GB / macOS 27.0 · llama.cpp b11005 official
`llama-b11005-bin-macos-arm64` release binaries (SHA-256 verified) ·
Qwen2.5-1.5B-Instruct Q4_K_M (1.04 GiB, 1.78 B params).

### Throughput — `llama-bench -p 256 -n 64 -r 3`

| Backend | Prompt processing (pp256) | Generation (tg64) |
|---|---|---|
| Metal (`-ngl 99`) | 1033.10 ± 2.38 t/s | 85.13 ± 0.20 t/s |
| CPU (`-ngl 0`, 4 threads) | 289.56 ± 4.43 t/s | 67.12 ± 0.84 t/s |

### Real transform request — `llama-completion`, Metal, temp 0, ctx 512

Input: "create a function called get user by id that accepts a string id and returns a promise of user or null"

| Prompt | Run | Model load | Prompt eval | Generation | Process wall | Max RSS |
|---|---|---|---|---|---|---|
| Zero-shot system prompt (98 tokens) | 1st | 302.7 ms | 302.2 ms | 436.6 ms / 37 tok | 2.60 s | 1.26 GB |
| Zero-shot system prompt (98 tokens) | 2nd | 144.8 ms | 144.4 ms | 435.7 ms / 37 tok | 0.95 s | 1.26 GB |
| Few-shot prompt (167 tokens) | warm cache | — | 195.7 ms | 234.2 ms / 20 tok | — | — |
| Few-shot prompt, "next js api route…postgres q l" (165 tokens) | warm cache | — | 200.4 ms | 211.8 ms / 18 tok | — | — |

(Process wall includes process startup, binary loading and tokenizer init, so it isn't what
in-app latency will be. The in-app number is prompt eval + generation, ≈ 0.4 s here.)

### Output quality
- **Zero-shot → spec violation:** produced a ```` ```typescript ```` block with an `import` and a function body.
- **Few-shot →** `Create a function called getUserById that accepts a string id and returns a promise of user or null.`
  and `Create a Next.js API route that validates the request body and stores the user in PostgreSQL.`
  Correct, but the type phrase wasn't converted to `Promise<User | null>`.

### Takeaways
- Warm Smart Mode cost ≈ 0.4 s for a short sentence, dominated by generation (≈ 11.8 ms/token).
  Output length drives latency.
- Prefix KV-cache reuse would remove most of the ~200 ms prompt-eval cost.
- 1.26 GB RSS while loaded. Load-on-demand with an idle unload is the likely strategy.

### Still to measure (Phase 7)
In-app cold/warm via the C API, 0.5B vs 1.5B vs Gemma 3 1B vs Llama 3.2 1B quality and latency,
GPU time, RAM after unload, coexistence with whisper in one process.
