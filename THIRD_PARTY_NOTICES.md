# Third-party notices

VoiceFlow itself is MIT licensed (see [LICENSE](LICENSE)). It has **no Swift package dependencies**. The parts below are
downloaded at setup time by `scripts/fetch-deps.sh` and `scripts/fetch-models.sh`; they are never committed to this
repository and never downloaded while dictating.

## whisper.cpp (and ggml)

- Source: <https://github.com/ggml-org/whisper.cpp>, release `b5130`, prebuilt `whisper.xcframework`
- License: MIT — Copyright (c) 2023-2024 The ggml authors
- Used as: the speech-recognition runtime, loaded only by the `voiceflow-stt` helper process
- Pinned version and checksum: `scripts/fetch-deps.sh`; rationale in `docs/ARCHITECTURE.md` §6

## Whisper models (OpenAI) in ggml format

- Weights: <https://huggingface.co/ggerganov/whisper.cpp> (ggml conversions of OpenAI Whisper), plus the matching Core ML
  encoders (`*-encoder.mlmodelc`)
- License: MIT — Copyright (c) 2022 OpenAI; the ggml conversions are published under the same terms
- Models used: `medium.en-q8_0` (English), `large-v3-turbo-q8_0` (Hindi/Hinglish and language detection),
  `large-v3-q5_0` (German, optional). Each file's SHA-256 is verified on download (`scripts/fetch-models.sh`) and again
  before first use.

## Apple frameworks

AppKit, AVFoundation, SwiftUI, Speech, ServiceManagement, OSLog, CryptoKit and FoundationModels (Apple's on-device
language model, used for the optional rewrite modes) are part of macOS and used under Apple's SDK terms. No Apple code is
redistributed here.

## Benchmark material

The sentence corpora in `benchmarks/` were written for this project and are covered by this repository's license.
Voice recordings used for the accuracy benchmarks stay on the machine that made them (`benchmarks-output/`, gitignored)
and are not part of this repository.
