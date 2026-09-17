#!/usr/bin/env python3
"""Derives per-script corpora (developer-speech format) from benchmarks/corpus/multilingual.json (Phase 14):
  benchmarks-output/corpus-de.json            German (spoken = reference = text)
  benchmarks-output/corpus-hi-devanagari.json Hindi scored in Devanagari (English words in Latin)
  benchmarks-output/corpus-hinglish.json      the same Hindi speech scored in romanized Hinglish
  benchmarks-output/corpus-hi-record.json     for scripts/bench/record.sh: shows Devanagari with the Hinglish line below
"""
import json, os
root = os.path.join(os.path.dirname(__file__), "..", "..")
entries = json.load(open(os.path.join(root, "benchmarks/corpus/multilingual.json")))["entries"]
out = os.path.join(root, "benchmarks-output"); os.makedirs(out, exist_ok=True)
def write(name, rows):
    json.dump({"version": 1, "entries": rows}, open(os.path.join(out, name), "w"), ensure_ascii=False, indent=1)
    print(f"{len(rows)} entries → benchmarks-output/{name}")
de = [e for e in entries if e["language"] == "de"]
hi = [e for e in entries if e["language"] == "hi"]
base = lambda e: {"id": e["id"], "category": e["category"], "synthesizable": True, "terms": e["terms"]}
write("corpus-de.json", [base(e) | {"spoken": e["text"], "reference": e["text"]} for e in de])
write("corpus-hi-devanagari.json", [base(e) | {"spoken": e["devanagari"], "reference": e["devanagari"]} for e in hi])
write("corpus-hinglish.json", [base(e) | {"synthesizable": False, "spoken": e["hinglish"], "reference": e["hinglish"]} for e in hi])
write("corpus-hi-record.json", [base(e) | {"spoken": e["devanagari"] + "\n   (" + e["hinglish"] + ")", "reference": e["devanagari"]} for e in hi])
