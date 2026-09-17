#!/usr/bin/env python3
"""Smart Mode benchmark harness for llama.cpp models (developer tool, not part of the app).
Starts the official llama-server for one model on localhost (benchmark only; VoiceFlow never runs a server), sends each
cleanup entry as system + few-shot chat, temperature 0, and writes JSONL for `vf-bench cleanup`.

  scripts/bench/llm_llama.py <llama-server> <model.gguf> benchmarks-output/cleanup-corpus.json prompts/clean.json <out.jsonl> <run>
"""
import json, os, subprocess, sys, time, urllib.request

server, model, corpus_path, prompt_path, out_path, run = sys.argv[1:7]
port = 18087
entries = json.load(open(corpus_path))["entries"]
prompt = json.load(open(prompt_path))

proc = subprocess.Popen([server, "-m", model, "-ngl", "99", "-c", "4096", "--port", str(port), "--host", "127.0.0.1",
                         "-np", "1", "--no-webui"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
def call(path, body=None, timeout=120):
    req = urllib.request.Request(f"http://127.0.0.1:{port}{path}", data=json.dumps(body).encode() if body else None,
                                 headers={"Content-Type": "application/json"})
    return json.load(urllib.request.urlopen(req, timeout=timeout))
try:
    t0 = time.time()
    while True:
        try:
            if call("/health").get("status") == "ok": break
        except Exception: pass
        if proc.poll() is not None: sys.exit("server exited")
        time.sleep(0.2)
    load_s = time.time() - t0
    messages = [{"role": "system", "content": prompt["system"]}]
    for ex in prompt["examples"]:
        messages += [{"role": "user", "content": ex["input"]}, {"role": "assistant", "content": ex["output"]}]
    call("/v1/chat/completions", {"messages": messages + [{"role": "user", "content": "uh hello there"}], "temperature": 0, "max_tokens": 16})
    rss = subprocess.run(["ps", "-o", "rss=", "-p", str(proc.pid)], capture_output=True, text=True).stdout.strip()
    with open(out_path, "w") as out:
        for e in entries:
            words = len(e["input"].split())
            t = time.time()
            r = call("/v1/chat/completions", {"messages": messages + [{"role": "user", "content": e["input"]}],
                                              "temperature": 0, "max_tokens": int(words * 2.5) + 32, "cache_prompt": True})
            latency = time.time() - t
            timings = r.get("timings", {})
            out.write(json.dumps({"type": "clip", "run": run, "id": e["id"],
                                  "output": r["choices"][0]["message"]["content"].strip(), "latency_s": latency,
                                  "prompt_ms": timings.get("prompt_ms"), "predicted_ms": timings.get("predicted_ms"),
                                  "output_tokens": r.get("usage", {}).get("completion_tokens")}) + "\n")
    print(f"{run}: load {load_s:.2f} s, server RSS {int(rss)/1024:.0f} MB, {len(entries)} entries")
finally:
    proc.terminate(); proc.wait(timeout=10)
