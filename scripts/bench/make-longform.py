#!/usr/bin/env python3
"""Builds long-form dictation clips (60–110 s) from a microphone's human recordings: several clips in sequence
separated by pauses of low-level room noise, like a real dictation where the speaker stops to think.
The reference text is the concatenated spoken text (with that microphone's spoken-overrides.json applied).

  scripts/bench/make-longform.py macbook-mic
  → benchmarks-output/audio/longform/<mic>/longform-NN.wav + benchmarks-output/longform-corpus.json
Deterministic (fixed seed). Development tool only.
"""
import json, os, random, sys, wave
import numpy as np

mic = sys.argv[1] if len(sys.argv) > 1 else "macbook-mic"
root = os.path.join(os.path.dirname(__file__), "..", "..")
src = os.path.join(root, "benchmarks-output", "audio", "human", mic)
out = os.path.join(root, "benchmarks-output", "audio", "longform", mic)
os.makedirs(out, exist_ok=True)

corpus = json.load(open(os.path.join(root, "benchmarks", "corpus", "developer-speech.json")))["entries"]
overrides_path = os.path.join(src, "spoken-overrides.json")
overrides = json.load(open(overrides_path)) if os.path.exists(overrides_path) else {}
entries = [e for e in corpus if os.path.exists(os.path.join(src, e["id"] + ".wav"))]

rng = random.Random(7)
nprng = np.random.default_rng(7)
noise_rms = 10 ** (-58 / 20)  # measured room noise floor for this mic: −55…−64 dBFS

def read(path):
    with wave.open(path) as w:
        assert w.getframerate() == 16000 and w.getnchannels() == 1
        return np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float32) / 32768

long_entries = []
order = entries[:]
rng.shuffle(order)
index, n = 0, 0
while index < len(order) and n < 8:
    n += 1
    parts, spoken, terms, total = [], [], [], 0.0
    target = rng.uniform(60, 110)
    while index < len(order) and total < target:
        e = order[index]; index += 1
        audio = read(os.path.join(src, e["id"] + ".wav"))
        pause = rng.uniform(1.5, 4.0)
        parts.append(audio)
        parts.append((nprng.standard_normal(int(pause * 16000)) * noise_rms).astype(np.float32))
        spoken.append(overrides.get(e["id"], e["spoken"]))
        terms.extend(e["terms"])
        total += len(audio) / 16000 + pause
    samples = np.concatenate(parts)
    lid = f"longform-{n:02d}"
    with wave.open(os.path.join(out, lid + ".wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(16000)
        w.writeframes((np.clip(samples, -1, 1) * 32767).astype(np.int16).tobytes())
    text = " ".join(spoken)
    long_entries.append({"id": lid, "category": "natural", "synthesizable": False, "terms": terms,
                         "spoken": text, "reference": text})
    print(f"{lid}: {len(samples)/16000:.1f} s, {len(spoken)} utterances, {len(text.split())} words")

json.dump({"version": 1, "entries": long_entries},
          open(os.path.join(root, "benchmarks-output", "longform-corpus.json"), "w"), indent=1)
