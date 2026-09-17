#!/usr/bin/env python3
"""Builds the Smart Mode cleanup corpus: real STT output (voiceflow-stt benchmark JSONL) + hand-written traps.
  scripts/bench/make-cleanup-corpus.py benchmarks-output/results/helper/clips.jsonl benchmarks-output/results/helper/long.jsonl
  → benchmarks-output/cleanup-corpus.json   (entries: id, category, input, reference, terms)
  → benchmarks-output/cleanup-corpus-spoken.json (spoken forms, lowercase, no punctuation: Developer mode)
"""
import json, os, sys
root = os.path.join(os.path.dirname(__file__), "..", "..")
speech = {e["id"]: e for e in json.load(open(os.path.join(root, "benchmarks/corpus/developer-speech.json")))["entries"]}
longform_path = os.path.join(root, "benchmarks-output/longform-corpus.json")
if os.path.exists(longform_path):
    speech.update({e["id"]: e for e in json.load(open(longform_path))["entries"]})
entries = []
for path in sys.argv[1:]:
    for line in open(path):
        j = json.loads(line)
        if j.get("type") != "clip" or j["id"] not in speech: continue
        e = speech[j["id"]]
        entries.append({"id": "stt-" + j["id"], "category": "stt-" + e["category"], "input": j["text"],
                        "reference": e["reference"], "terms": e["terms"]})
entries += json.load(open(os.path.join(root, "benchmarks/corpus/cleanup-traps.json")))["entries"]
json.dump({"version": 1, "entries": entries}, open(os.path.join(root, "benchmarks-output/cleanup-corpus.json"), "w"), indent=1)
print(f"{len(entries)} entries → benchmarks-output/cleanup-corpus.json")

# Spoken-form corpus (Phase 8, Developer mode): the corpus `spoken` text as an STT engine without the vocabulary prompt
# would write it (lowercase, no punctuation, symbols as words), scored against the written reference.
import re
spoken = [{"id": "spoken-" + e["id"], "category": "spoken-" + e["category"],
           "input": re.sub(r"[.,?!]", "", e["spoken"]).lower(), "reference": e["reference"], "terms": e["terms"]}
          for e in speech.values() if "spoken" in e and not e["id"].startswith("long")]
json.dump({"version": 1, "entries": spoken}, open(os.path.join(root, "benchmarks-output/cleanup-corpus-spoken.json"), "w"), indent=1)
print(f"{len(spoken)} entries → benchmarks-output/cleanup-corpus-spoken.json")
