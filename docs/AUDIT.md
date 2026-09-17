# Final audit (Phase 13)

Date: 2026-09-17 · VoiceFlow 1.0.0 · MacBook Air M4, 16 GB, macOS 27.0 · installed at `~/Applications/VoiceFlow.app`.
Every result below was measured or run on this machine on this date unless it cites an earlier section.

## Summary

| Area | Verdict | Key evidence |
|---|---|---|
| Accuracy | **Pass** | STT on the owner's 50 recordings: WER 1.1%, terms 97.4%, 0 invented phrases; transcripts identical to the approved gate (50/50, long-form 7/7) |
| Performance | **Pass** | Idle 13 MB, 0.01 s CPU/60 s, 0 GPU; launch 101 ms; short dictation release → text ~0.6–0.9 s |
| Privacy | **Pass** | No network code or frameworks; 0 sockets and 0 files during a full dictation; 0 log lines with spoken words |
| Reliability | **Pass** | Damaged/missing model, helper crash, rewrite failure, paste failure, permission denied: clear errors, no crash, speech kept where possible |
| UX | **Pass** | Red icon + pill when audio flows; ⌥ dispatch ≤ 1.7 ms; pill never takes focus; window only when asked |

## 1. Accuracy

| Check | Threshold (ACCURACY §3) | Result 2026-09-17 |
|---|---|---|
| STT WER, owner recordings (installed helper, Core ML encoder) | ≤ 5% | **1.1%** |
| WER normal English | ≤ 3% | 0.0% |
| Technical terms heard | ≥ 95% | **97.4%** (76/78) |
| Per category ≥ 90% (categories with ≥ 20 terms) | ≥ 90% | technical 100% (24/24) |
| Invented phrases | ≤ 1 per 100 | **0** |
| Long-form dictations (7) | — | WER 0.7%, identical to Phase 6 |
| Transcripts vs approved Phase 6 run | — | identical 50/50 and 7/7 |
| Clean / Developer rules (72 real + trap entries) | 0 unsafe | 0 unsafe; formatting error 15.6% → 10.6% / 10.5% (Developer's 1 flagged change is the intended nginx.com → nginx.conf) |
| Developer corrections + Code mode (49) | 0 over-corrections | 17/17, 10/10, traps 22/22, **0 over-corrections** |
| Model modes (Apple on-device + guards) | 0 unsafe shipped | no trap output accepted; fallback on real transcripts 7–8 of 57; hand-reviewed (ACCURACY §7.4) |

## 2. Performance

| Measurement | Result | Source |
|---|---|---|
| Launch (kernel start → ready) | 101 ms (first launch after a build ~0.9 s) | `measure-idle.sh 60`, today |
| Idle CPU / wakeups / GPU / memory | 0.01 s per 60 s, 4 wakeups, 0 ms, **13 MB** | today |
| Quit | 247 ms | today |
| ⌥ trigger dispatch | 0.22–1.66 ms | PERFORMANCE §3.10 (owner use) |
| Press → audio flowing (built-in mic) | 172–187 ms warm | PERFORMANCE §5.5 |
| STT on owner recordings | mean 0.63 s, p95 1.15 s per clip | today |
| Short dictation release → text | ~0.6–0.9 s | PERFORMANCE §5.5 |
| Model rewrite (when used) | 0.6–2.6 s; 870 ms for a 20-word dictation today | today / §5.4 |
| Speech helper memory | 1.1–1.2 GB only while loaded; exits 60 s after last use | §3.9, §5.5 |
| Window open | 31 MB, 0.23% CPU | §5.6 |
| Disk | app 7.6 MB; models in use 1.39 GB | §5.5 |

## 3. Privacy

| Check | Method | Result |
|---|---|---|
| No network code | Source search in app, helper and core (URLSession, sockets, NWConnection, URLs) | none |
| No networking frameworks linked | `otool -L` on both installed binaries | none (Network/CFNetwork/WebKit absent) |
| No network activity | `lsof -i` on VoiceFlow and voiceflow-stt every 0.25 s through a full dictation with a model rewrite | **0 sockets** |
| Audio/transcripts not stored | Files written during that dictation (Application Support, /tmp, Caches) | **none** |
| Logs contain no speech | All log interpolations reviewed (metadata only); unified log searched for the spoken words after the dictation | **0 matches** |
| No telemetry, accounts or downloads at runtime | Source review; models installed only by `scripts/fetch-models.sh` (SHA-256 verified) | none |
| Clipboard | Snapshot → paste → restore if unchanged (tests: `restoresOnlyIfClipboardUnchangedSinceWrite`, round-trip tests) | restored |
| Rewrite model | Apple's on-device FoundationModels (system process on this Mac) | on-device |
| Files VoiceFlow writes | settings.json, dictionary.json, models/verified.json; debug WAVs only if `saveRecordingsForDebugging` is turned on (off) | as designed |

## 4. Reliability

| Failure | How verified | Behavior |
|---|---|---|
| Speech model damaged | Live today: truncated model copy + spoken test phrase | Recording kept; error "Speech model file is damaged (size …). Reinstall: scripts/fetch-models.sh whisper medium.en-q8_0"; app keeps running |
| Speech model missing | Live today: empty models folder | Detected at launch ("missing"); same error path with the install command; menu and window show the command |
| Speech helper crashes mid-transcription | Live (Phase 12): `kill -9` on the helper | "The speech helper stopped unexpectedly" with Retry (audio kept); next dictation starts a new helper |
| Rewrite model fails / unsafe / times out | Owner log ("Detected content likely to be unsafe" → cleaned transcript pasted); test `smartModeFailureStillInsertsTranscript`; 5 s timeout | Rule-cleaned text is pasted; nothing lost |
| Rewrite changes meaning | Guards + corpora (ACCURACY §6–7) | Rejected → rule-cleaned text |
| Paste impossible (no Accessibility, focus lost) | Tests `missingPermissionLeavesTextOnClipboard`, `focusChangeWithoutPermissionStillLeavesTextOnClipboard`, `pasteFailureIsReportedAndDismissible` | Text left on the clipboard with a message and Open Accessibility Settings |
| Microphone permission denied | Code path + test `microphoneDeniedRecoversAfterAccessIsGranted` | Error with Open Microphone Settings; next press works once allowed |
| Input Monitoring missing | Phase 6 fallback | ⌥Space trigger + menu/window instructions |
| Invalid settings or dictionary file | Tests `invalidValuesFallBackPerKey`, `tolerantLoading` | Defaults per key; invalid settings file preserved as settings.invalid.json |
| App killed with helper loaded | Phase 6 | Helper exits on its own (no orphan) |
| Input device changes while recording | Phase 3 | Stops with the audio captured so far |

Tests: 149 core + 5 app, all passing.

## 5. UX

| Check | Result |
|---|---|
| Recording feedback | Menu icon turns red and the pill shows live level bars when real audio flows; "Starting…" before that |
| Hotkey reliability | ⌥ hold / double-tap hands-free / Esc cancel; stale presses (menu open) ignored; ⌥Space fallback |
| Unobtrusive | Menu-bar app; pill is a non-activating panel (never steals focus) and hides when idle; Dock icon only while the window is open; window never opens at login |
| Mode per app | Correct in owner test (VS Code, WhatsApp, Chrome AI tab, Notes); detection ≤ 0.1 ms |
| Setup | Window Home checklist with live permission/model status and fix buttons; `scripts/install.sh` |

## Known limitations (accepted)

1. English only (`medium.en`); Hinglish and other languages need a multilingual model and fresh recordings.
2. Model modes add 0.6–2.6 s on long dictations; a rejected rewrite still costs that time (options measured in PERFORMANCE §5.4).
3. AirPods start capturing ~0.5 s after the press (the pill/icon show when audio flows); not yet confirmed in owner use.
4. Possessive number ("users session" → "user's" vs "users'") is the model's guess; guards can't see apostrophes (they only restore ones the transcript had).
5. Not corrected without context: "we don't need help for now" (Helm), "forms" vs "form's", ID vs Id.
6. Apple's on-device model can change with macOS updates: re-run `vf-bench modes` (DEVELOPMENT.md) after major updates.
7. Signed with a local identity, not notarized; declared minimum macOS 14 but tested only on macOS 27 (model modes need macOS 26+).
8. 5.0 GB of benchmark-only STT models remain in Application Support (deletable on request).
