# Memory benchmark

## Phase 0 sanity check (2026-09-16)

Release build of the empty Phase 0 shell (status item + 2-item menu), sampled ~3 s after launch:

| Metric | Value | Tool |
|---|---|---|
| phys_footprint | 13 MB | `footprint <pid>` |
| RSS (includes shared system frameworks) | 55.0 MB | `ps -o rss` |
| CPU | 0.0% | `ps -o %cpu` (single sample) |
| App bundle size | 68 KB (executable 60 KB) | `du -sh` |

Model-process peak RSS from Phase 0 harnesses is in `stt.md` and `llm.md`.

**Formal idle measurement (60 s sampling, GPU time): Phase 1.**
