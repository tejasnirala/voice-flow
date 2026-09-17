# Accuracy

Transcription accuracy is priority #1 (spec §2). This document defines how accuracy is measured, the
threshold a model must meet, and every result measured so far.

---

## 1. Corpus

`benchmarks/corpus/developer-speech.json`: **54 phrases** covering spec §4.

| Category     | Count | Examples                                                                                                                                                         |
| ------------ | ----- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| normal       | 6     | "The meeting has been moved to three o'clock."                                                                                                                   |
| technical    | 12    | "The database is PostgreSQL with Redis for caching." · RabbitMQ, MongoDB, JWT, OAuth, WebSocket, GraphQL, Prisma, Mongoose, AWS/Azure/GCP, Nginx                 |
| identifiers  | 8     | getUserById, refreshAccessToken, createInvoice, handleSubmit/onSubmit, isAuthenticated/userSession, snake_case/user_session_id, camelCase, useEffect/fetchOrders |
| commands     | 8     | npm run dev, npm install, git rebase main, docker compose up/down, kubectl get pods, git checkout -b feature/login, pnpm                                         |
| files        | 7     | package.json, tsconfig.json, docker-compose.yml, .env, .env.local, nginx.conf, DATABASE_URL                                                                      |
| architecture | 5     | "The access token expires after fifteen minutes and the refresh token lasts for one day."                                                                        |
| natural      | 4     | 20–30 s conversational developer explanations (and one non-technical update)                                                                                     |
| hinglish     | 4     | "Is function mein get user by id call karo aur result ko Redis mein cache kar do." (human recordings only)                                                       |

Each entry has:

- `spoken`: what the speaker says. Identifiers are spoken as words ("get user by id"), symbols as words ("dot env").
- `reference`: the ideal written result ("getUserById", ".env").
- `terms`: key terms that must be recognized. Alternate pronunciations can be listed:
  `kubectl get pods|kube control get pods|kube cuddle get pods`.

## 2. Audio sets

| Set           | How                                                                                                                                | Purpose                                                        | Limitations                                                                                                                                                                                                                                                                 |
| ------------- | ---------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **synthetic** | `scripts/bench/make-audio.sh`: macOS TTS voices Rishi (en-IN), Samantha (en-US), Daniel (en-GB); 50 clips each (Hinglish excluded) | Validate the pipeline; measure performance; rough shortlisting | TTS is clean and evenly paced, and **mispronounces** developer terms ("middle way" for middleware, "database urla" for DATABASE_URL). These show up as identical misses across every model, so the set **can't separate the good models**. Never the basis for the decision |
| **human**     | `scripts/bench/record.sh <mic-label>`: the owner reads the corpus naturally on each microphone they dictate with                   | **The decision set**                                           | One speaker (which is the actual user); a small set, so ±1 term ≈ ±0.4 pp term accuracy                                                                                                                                                                                     |

Human clips are retained deliberately for benchmarking under `benchmarks-output/audio/human/` (gitignored,
never committed, deletable at any time).

## 3. Metrics & proposed threshold

Scoring code: `Sources/VoiceFlowCore/Speech/Accuracy/` (14 unit tests). Report: `vf-bench score`.

| Metric               | Definition                                                                                                                                                                                                                                                                                                                                                           | Why                                                      |
| -------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------- |
| **WER**              | Word error rate of the raw STT output against the **spoken** words. Case- and punctuation-insensitive. Number words = digits ("fifteen" = "15"). A term the engine recognized counts as one word in any spelling ("getUserById" = "get user by id"). A misheard term is scored word by word. Spoken symbol words ("dot", "slash", "dash", "underscore") are excluded | Did it hear the words?                                   |
| **Term recognition** | Share of key terms heard correctly in any spelling or listed pronunciation. "Postgresql", "PostgreSQL", "postgres QL" ✓; "post-guessql" ✗                                                                                                                                                                                                                            | The developer-vocabulary requirement (spec §2, §13)      |
| **Exact terms**      | Share of key terms with the exact canonical spelling in the raw output ("Next.js", "getUserById")                                                                                                                                                                                                                                                                    | How much formatting is left for Developer mode (Phase 9) |
| **Formatting WER**   | Token error rate against the written reference, case- and punctuation-sensitive                                                                                                                                                                                                                                                                                      | Proxy for punctuation/capitalization quality             |
| Per-category WER     | WER within each category                                                                                                                                                                                                                                                                                                                                             | Catch a model that's good on prose but bad on commands   |
| Hallucination check  | Manual review of error listings: terms inserted that weren't said (especially with vocabulary prompts)                                                                                                                                                                                                                                                               | Rules 8–9                                                |

Limitation: automatic metrics can't judge whether a punctuation choice is _acceptable_ (e.g. comma vs
period). Formatting WER is a proxy. The error listing is reviewed by hand for the final decision.

### Acceptance threshold (**approved by owner, 2026-09-17**)
Measured on the **human** set, per microphone the owner dictates with. The owner may revise it later.

| Criterion | Threshold |
|---|---|
| Overall WER | **≤ 5 %** |
| Normal-English WER | **≤ 3 %** |
| Key-term recognition, all categories combined | **≥ 95 %** |
| Key-term recognition, per category | **≥ 90 %**, applied to categories with ≥ 20 term occurrences in the evaluated set (pool takes to reach it) |
| Invented phrases | **≤ 1 per 100 clips** |
| Latency sanity bound (not a ranking criterion) | warm p95 ≤ 2 s for clips ≤ 10 s |

**Invented phrase** (scorer: `AccuracyScorer.insertedRuns`, 3 tests): 2+ consecutive output words that weren't spoken,
bounded by correctly recognized words. A single extra word ("with **a** Redis") is an ordinary error (counted in WER).
Extra words next to a misrecognized word ("PostgreSQL" → "post gray sql") are a split misrecognition (counted in WER
and term recognition).

**Reviewed references:** when the speaker's words differ from the corpus script, the owner confirms what was said, and
the correction goes in `benchmarks-output/audio/human/<mic>/spoken-overrides.json` (applied by
`scripts/bench/stt.sh` / `vf-bench --overrides-dir`).

**Selection rule (spec §23):** keep only models meeting every accuracy criterion. Among those, choose the
lowest warm latency. If latencies are within ~20 %, choose the lower memory footprint. If **no** model
meets the threshold: pick the most accurate, try vocabulary prompting (measured for hallucinations), and
do not pass the Phase 4 gate until it's resolved (a better model, or an owner decision on the threshold).

## 4. Candidates

| Candidate                                       | Runtime                    | Why considered                                                                                                      | Size on disk |
| ----------------------------------------------- | -------------------------- | ------------------------------------------------------------------------------------------------------------------- | ------------ |
| Whisper small.en                                | whisper.cpp                | Baseline; fastest plausible English model                                                                           | 465 MB       |
| Whisper medium.en q8_0                          | whisper.cpp                | English-only accuracy tier, quantized                                                                               | 785 MB       |
| Whisper large-v3-turbo (f16)                    | whisper.cpp                | Near large-v3 accuracy with a 4-layer decoder; multilingual (Hinglish possible)                                     | 1549 MB      |
| Whisper large-v3-turbo q8_0                     | whisper.cpp                | Same, half the size: measures quantization loss                                                                     | 834 MB       |
| Whisper large-v3-turbo q8_0 + vocabulary prompt | whisper.cpp                | Developer-term biasing via `initial_prompt` (hallucination risk measured)                                           | 834 MB       |
| Whisper distil-large-v3                         | whisper.cpp                | Distilled large-v3, English                                                                                         | 1449 MB      |
| NVIDIA Parakeet TDT 0.6B v3 q8_0                | whisper.cpp (`parakeet.h`) | Top-tier English accuracy on public leaderboards, very fast transducer; same framework, no new dependency. No Hindi | 638 MB       |
| Apple SpeechTranscriber (en-US, en-IN)          | macOS Speech framework     | Zero dependency; OS-managed model; ~20 MB in-process                                                                | OS-managed   |
| Apple SpeechTranscriber + contextual strings    | macOS Speech framework     | Native vocabulary biasing                                                                                           | OS-managed   |

Not benchmarked (and why):

- **tiny.en / base.en:** failed developer terms in the v1 exploration (e.g. "post-guessql", "npm run they've");
  below the accuracy tier. The accuracy-first rule says not to pursue them.
- **large-v3 (full):** 2.9 GB. large-v3-turbo is the practical ceiling to try first. Added if nothing
  meets the threshold.
- **MLX Whisper:** Python runtime (not allowed in-app); same Whisper weights, so no accuracy difference
  expected. Its only possible advantage is speed, which matters only after accuracy is settled.
- **WhisperKit (CoreML/ANE):** same weights. A heavier dependency chain. Reconsidered in Phase 6 only if
  whisper.cpp latency is unacceptable.

## 5. Results

### 5.1 Synthetic set, 2026-09-16/17 (shortlisting only)

**Conditions:** whisper.cpp b5130 prebuilt framework (Metal, flash attention, 4 threads, greedy, language
`en`, no timestamps); Parakeet via the same framework (Metal, greedy); Apple SpeechTranscriber on macOS 27.0.
50 clips × 3 TTS voices (Rishi en-IN, Samantha en-US, Daniel en-GB) = 150 clips per configuration,
234 key-term occurrences. Report: `benchmarks-output/results/synthetic/report.md` (reproduce with
`scripts/bench/make-audio.sh && scripts/bench/stt.sh synthetic`).

| Configuration                                      | WER      | normal | technical | identifiers | commands | files | architecture | natural | **Terms**       | Exact | Fmt WER |
| -------------------------------------------------- | -------- | ------ | --------- | ----------- | -------- | ----- | ------------ | ------- | --------------- | ----- | ------- |
| whisper large-v3-turbo (f16)                       | **2.2%** | 0.0%   | 5.6%      | 3.6%        | 5.8%     | 1.7%  | 0.6%         | 0.4%    | **91.9%** (215) | 69.2% | 11.8%   |
| whisper large-v3-turbo q8_0                        | **2.3%** | 0.0%   | 5.6%      | 3.6%        | 6.4%     | 1.7%  | 0.6%         | 0.4%    | **91.5%** (214) | 68.4% | 11.7%   |
| whisper large-v3-turbo q8_0 + vocabulary prompt    | 2.4%     | 0.0%   | 3.9%      | 5.2%        | 9.2%     | 3.4%  | 0.6%         | 0.4%    | 92.3% (216)     | 71.8% | 11.5%   |
| whisper medium.en q8_0                             | 2.8%     | 0.0%   | 5.0%      | 3.7%        | 5.8%     | 3.4%  | 3.6%         | 1.3%    | 91.5% (214)     | 62.0% | 11.4%   |
| whisper small.en                                   | 2.8%     | 0.5%   | 5.0%      | 2.2%        | 8.1%     | 1.7%  | 4.2%         | 1.2%    | 90.6% (212)     | 62.0% | 12.3%   |
| Parakeet TDT 0.6B v3 q8_0                          | 3.7%     | 0.5%   | 8.6%      | 3.1%        | 5.0%     | 9.0%  | 3.6%         | 0.9%    | 85.0% (199)     | 54.3% | 14.7%   |
| whisper distil-large-v3                            | 6.3%     | 1.6%   | 9.4%      | 4.2%        | 11.5%    | 16.7% | 8.4%         | 2.8%    | 76.9% (180)     | 41.0% | 17.8%   |
| Apple SpeechTranscriber en-US                      | 11.1%    | 0.0%   | 18.1%     | 8.6%        | 18.7%    | 26.9% | 15.6%        | 5.1%    | 58.5% (137)     | 18.4% | 24.7%   |
| Apple SpeechTranscriber en-US + contextual strings | 11.1%    | 0.0%   | 18.1%     | 8.6%        | 18.7%    | 26.9% | 15.6%        | 5.1%    | 58.5% (137)     | 18.4% | 24.7%   |
| Apple SpeechTranscriber en-IN                      | 11.2%    | 0.0%   | 18.1%     | 8.6%        | 18.7%    | 26.9% | 15.6%        | 5.5%    | 58.5% (137)     | 18.4% | 24.9%   |

Latency and memory for the same runs: PERFORMANCE.md §3.

### 5.2 What the synthetic set shows (and doesn't)

**Shared TTS artifacts.** Many misses are identical across _every_ model, because the TTS voice
mispronounced the term: "middle way" (middleware), "deploy tools / two of us" ("deploy to AWS"),
"database urla" (DATABASE_URL), "Jitra base" (git rebase), "Cuba Control" (kube control), "eid" (id).
Every Whisper model tops out at ~91–92% term recognition largely **because of the audio**, so this set
**can't** separate small.en, medium.en and large-v3-turbo. The threshold can't be evaluated on it either.

**What it does establish:**

1. **Apple SpeechTranscriber is eliminated.** 58.5% term recognition; files 26.9% WER. Contextual strings
   produced byte-identical output (no measurable effect), and en-IN behaved the same as en-US.
2. **distil-large-v3 is eliminated.** Worse than small.en on every developer category, and slower than large-v3-turbo.
3. **q8_0 quantization costs no measurable accuracy** for large-v3-turbo (2.2% vs 2.3% WER; 215 vs 214
   terms, one term = 0.4 pp) while using ~780 MB less memory and running ~16% faster, so **q8_0 replaces f16**.
4. **The Whisper vocabulary prompt isn't justified so far.** +2 terms, but it introduced new errors
   ("Prizma", dropped words) and made transcription a median 1.6× (up to 6×) slower (PERFORMANCE.md §3).
   No hallucinated technical terms appeared in normal-English clips (normal WER 0.0%).
   Re-test on the human set before discarding.
5. **Parakeet is behind on developer vocabulary** beyond the shared TTS artifacts: its own misses include
   "post-Gare SQL"/"Postgar SQL", "Gink" (Nginx), "Chrisma" (Prisma), "Oath" (OAuth), "NPM run Dave",
   "nginex.conf". It's by far the fastest local candidate, so it stays on the human-set list as a
   speed reference, but it's not favored.

### 5.3 Shortlist for the human-voice benchmark

| Finalist                                     | Why                                                                                                              |
| -------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| **whisper large-v3-turbo q8_0**              | Lowest WER; best technical/files/architecture/natural; multilingual (Hinglish possible). **Provisional default** |
| whisper medium.en q8_0                       | Same term recognition on synthetic, ~30% faster                                                                  |
| whisper small.en                             | Surprisingly close on synthetic; if it holds up on real speech it's ~4× faster and ~350 MB smaller               |
| Parakeet TDT 0.6B v3 q8_0                    | Speed reference; must prove itself on real speech                                                                |
| + large-v3-turbo q8_0 with vocabulary prompt | Only kept if it improves real speech without hallucinations                                                      |

### 5.4 Human set, macbook-mic, 2026-09-17 (the decision set)

**Conditions:** owner's voice, MacBook Air built-in microphone, recorded with `scripts/bench/record.sh`;
50 clips (Hinglish not recorded), 450 s total, 4.9–39.2 s per clip; 78 key-term occurrences. Engines and
settings as §5.1, plus `+vocab` runs for small.en and medium.en. Scored with the contraction fix and the
owner-confirmed kubectl pronunciation (§5.5). Report: `benchmarks-output/results/human/report.md`.

| Configuration | WER | normal | technical | identifiers | commands | files | architecture | natural | **Terms** | Exact | Fmt WER |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **whisper large-v3-turbo q8_0 + vocab** | **1.8%** | 0.0% | 1.7% | 0.0% | 0.0% | 0.0% | 3.6% | 3.0% | **98.7%** (77/78) | 73.1% | 11.6% |
| whisper medium.en q8_0 + vocab | 2.1% | 0.0% | 1.7% | 0.0% | 0.0% | 7.5% | 5.5% | 2.2% | 97.4% (76/78) | 79.5% | 12.4% |
| whisper large-v3-turbo (f16) | 2.0% | 0.0% | 1.7% | 0.0% | 2.3% | 0.0% | 7.3% | 2.2% | 94.9% (74/78) | 60.3% | 14.1% |
| whisper large-v3-turbo q8_0 | 2.1% | 0.0% | 1.7% | 0.0% | 2.3% | 0.0% | 9.1% | 2.2% | 93.6% (73/78) | 59.0% | 15.1% |
| whisper medium.en q8_0 | 2.9% | 0.0% | 3.3% | 0.0% | 2.3% | 10.0% | 5.5% | 2.6% | 93.6% (73/78) | 64.1% | 14.8% |
| whisper small.en + vocab | 4.0% | 0.0% | 3.3% | 1.6% | 18.0% | 10.0% | 3.6% | 2.2% | 93.6% (73/78) | 70.5% | 17.3% |
| whisper small.en | 4.1% | 0.0% | 7.5% | 0.0% | 2.3% | 10.0% | 10.9% | 2.2% | 92.3% (72/78) | 65.4% | 16.4% |
| whisper distil-large-v3 | 6.5% | 1.5% | 8.3% | 1.6% | 6.4% | 19.6% | 12.7% | 4.3% | 76.9% (60/78) | 42.3% | 19.6% |
| Parakeet TDT 0.6B v3 q8_0 | 6.7% | 1.5% | 8.3% | 1.6% | 12.2% | 18.6% | 16.4% | 3.0% | 80.8% (63/78) | 48.7% | 17.6% |
| Apple SpeechTranscriber en-US (± contextual strings) | 11.0% | 0.0% | 16.4% | 11.1% | 8.3% | 28.9% | 16.4% | 7.2% | 62.8% (49/78) | 24.4% | 24.2% |
| Apple SpeechTranscriber en-IN | 11.9% | 1.5% | 14.8% | 14.1% | 15.4% | 28.9% | 21.4% | 6.4% | 59.0% (46/78) | 21.8% | 25.8% |

Term recognition by category (proposed threshold: every category ≥ 90%):

| Configuration | technical | identifiers | commands | files | architecture | natural |
|---|---|---|---|---|---|---|
| **large-v3-turbo q8_0 + vocab** | 100% (24/24) | 100% (12/12) | 100% (8/8) | 100% (9/9) | 100% (10/10) | 93.3% (14/15) |
| medium.en q8_0 + vocab | 100% (24/24) | 100% (12/12) | 100% (8/8) | **88.9%** (8/9) | 100% (10/10) | 93.3% (14/15) |
| large-v3-turbo (f16) | 100% | 100% | 87.5% | 100% | 80.0% | 93.3% |
| large-v3-turbo q8_0 | 100% | 100% | 87.5% | 100% | 70.0% | 93.3% |
| medium.en q8_0 | 95.8% | 100% | 87.5% | 77.8% | 100% | 93.3% |
| small.en + vocab | 100% | 100% | 62.5% | 88.9% | 100% | 93.3% |
| small.en | 95.8% | 100% | 87.5% | 88.9% | 80.0% | 93.3% |

**Every remaining error of the two finalists (reviewed by hand):**

| Clip | large-v3-turbo q8_0 + vocab | medium.en q8_0 + vocab |
|---|---|---|
| natural-03 | ❌ "help" for **Helm** (owner confirmed "Helm" was said) | ❌ same |
| natural-01 | ❌ **inserted** "run dev": "run npm install, run dev and then npm run dev" (not spoken) | ✓ |
| files-06 | ✓ | ❌ "nginx.**com**" for nginx.conf (changes meaning) |
| commands-06 | "cube control get pods": accepted pronunciation of kubectl (owner, D2) | ✓ "kubectl" |
| (shared by *all* Whisper runs; D1 pending) | "with **a** Redis", "documents **to** MongoDB", "message… result", dropped "the" (natural-01/02), "into Redis", "cache **the** responses" | same |

### 5.5 Findings from the human set

1. **Real speech separates the models; synthetic speech didn't.** Without the vocabulary prompt, every
   Whisper model misses 4–6 of 78 terms ("gate rebase" for git rebase, "Radis", "Reddish", "radius",
   "PostgresSQL", "Rabit Amq", "nginx.com", "QuestGrace SQL"). **No configuration without the prompt meets
   the ≥95% term threshold** (best: large-v3-turbo f16, 94.9%).
2. **The vocabulary prompt is decisive on real speech.** +4 terms for both large-v3-turbo q8_0 and medium.en,
   at +11% / +14% latency (unlike the median 1.6× on synthetic audio). No technical terms were inserted into
   normal-English clips (normal WER 0.0%). **But** large-v3-turbo + vocab inserted an unspoken phrase once
   (natural-01): a hallucination the current threshold doesn't capture (see D3). small.en + vocab degraded
   commands badly ("npm rendev", "rungit").
3. **Helm → "help" in every model**, prompt included (owner confirmed "Helm"). It's a genuine limit for now;
   Phase 9 vocabulary work should target it.
4. **Eliminated on real speech:** small.en (±vocab), distil-large-v3, Parakeet (80.8%), Apple SpeechTranscriber (≤62.8%).
5. **Scoring corrections, all owner-visible:** (a) contractions and "ok/okay" are equivalent (previously
   the *entire* 3.2% normal-English WER); (b) "cube control get pods" is an accepted pronunciation of
   `kubectl get pods` (owner decision D2); formatting to `kubectl` belongs to Developer mode. No other numbers changed.

### 5.6 Owner review (2026-09-17)

| Item | Decision |
|---|---|
| D1 reading variations | Confirmed as spoken: "with **a** Redis" (technical-03), "documents **to** MongoDB" (technical-04), "message… result" (architecture-04), no "the" + "**into** Redis" (natural-01), no "the" before useEffect (natural-02). Scripted as spoken: "cache responses" (architecture-05; medium.en's "cache **the** responses" is a real 1-word insertion), "git rebase" (commands-03), "Helm" (natural-03). → `spoken-overrides.json` (5 clips) |
| D2 "cube control" | Accepted pronunciation of kubectl |
| D3 threshold | Approved as above, including the invented-phrase criterion |
| D4 more data | Recommendation accepted: **don't** save everyday dictations (unlabeled audio can't be scored; privacy default). Record a second scripted take instead (confirmation, not blocking) |

### 5.7 Human set re-scored with reviewed references (2026-09-17)

| Configuration | WER | normal | technical | Terms | Technical terms (24) | Invented phrases |
|---|---|---|---|---|---|---|
| whisper large-v3-turbo q8_0 + vocab | **0.5%** | 0.0% | 0.0% | **98.7%** (77/78) | 100% | **1 (2.0 per 100)**: "run dev" (natural-01) |
| **whisper medium.en q8_0 + vocab** | **1.1%** | 0.0% | 0.0% | **97.4%** (76/78) | 100% | **0** |
| whisper large-v3-turbo (f16) | 0.7% | 0.0% | 0.0% | 94.9% | 100% | 0 |
| whisper large-v3-turbo q8_0 | 0.8% | 0.0% | 0.0% | 93.6% | 100% | 0 |
| whisper medium.en q8_0 | 1.6% | 0.0% | 1.7% | 93.6% | 95.8% | 0 |
| whisper small.en + vocab | 3.1% | 0.0% | 3.3% | 93.6% | 100% | 0 |
| whisper small.en | 2.8% | 0.0% | 5.8% | 92.3% | 95.8% | 0 |
| whisper distil-large-v3 | 5.3% | 1.5% | — | 76.9% | 83.3% | 0 |
| Parakeet TDT 0.6B v3 q8_0 | 5.8% | 1.5% | 8.3% | 80.8% | 87.5% | 0 |
| Apple SpeechTranscriber en-US | 10.1% | 0.0% | 14.6% | 62.8% | 66.7% | 0 |

### 5.8 Phase 4 accuracy gate: decision (2026-09-17)

Applying the approved threshold and selection rule:

| Criterion | large-v3-turbo q8_0 + vocab | medium.en q8_0 + vocab |
|---|---|---|
| WER ≤ 5% | 0.5% ✓ | 1.1% ✓ |
| Normal WER ≤ 3% | 0.0% ✓ | 0.0% ✓ |
| Terms ≥ 95% | 98.7% ✓ | 97.4% ✓ |
| Per category ≥ 90% (technical, 24 occurrences) | 100% ✓ | 100% ✓ |
| Invented phrases ≤ 1 per 100 | 2.0 ✗ | 0 ✓ |
| **Result** | Fails | **Passes** |

**Chosen STT: Whisper medium.en q8_0 + developer vocabulary prompt** (now the app default). The only configuration
without the prompt that comes close (large-v3-turbo f16, 94.9%) fails the term criterion. In-app verification with
medium.en: `--transcribe-benchmark` on the 50 clips → **identical transcripts to the benchmark (50/50)**, WER 1.1%,
terms 97.4%, 0 invented phrases.

**Known weaknesses of the choice:** "nginx.com" for nginx.conf (a meaning-changing file-name error), and "help" for Helm
(all models). English-only: Hinglish would need large-v3-turbo. Phase 9 targets file names and tool names.

**Confidence:** one microphone, one take, 50 clips. The two finalists differ by one event, so a **second scripted take
is recommended to confirm** (`scripts/bench/record.sh macbook-mic-take2`, or with AirPods). If it changes the outcome,
switching is a one-line settings change (`sttModelID`).

