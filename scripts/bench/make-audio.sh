#!/usr/bin/env bash
# Generates synthetic 16 kHz mono test clips with macOS `say` into benchmarks-output/audio.
# Synthetic speech is cleaner than a real microphone: treat results as a lower bound
# on error rate. Real-voice recordings are added in Phase 4.
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT=benchmarks-output/audio; mkdir -p "$OUT"
gen() { say -o "$OUT/$1.wav" --data-format=LEI16@16000 "$2"; }
gen short     "Hello, this is a test."
gen medium    "Create a Next.js API route that validates the request body and stores the user in PostgreSQL."
gen developer "Create a function called get user by id that accepts a string ID and returns a Promise of User or null."
gen long      "So the plan for the authentication refactor is this. First, we move the token validation out of the Express middleware and into a dedicated service. The refresh token expires after one day, and we store the session in Redis so that the API response can be cached. Then we add a PostgreSQL index on the email column, run npm install, and then npm run dev to verify that everything still works locally before opening the pull request."
ls "$OUT"
