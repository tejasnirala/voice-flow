# Setting up VoiceFlow on your Mac

A complete, copy-paste walkthrough: from an empty Terminal to dictating into any app. Follow the steps in order.

Roughly 10 minutes of work plus 5–20 minutes of downloading (1.4 GB for English, 3.4 GB more for the other languages).
Everything below happens on your machine; the network is used only in steps 2 and 4, never while you dictate.

- [1. Check your Mac can run it](#1-check-your-mac-can-run-it)
- [2. Get the code](#2-get-the-code)
- [3. Create a signing identity (recommended)](#3-create-a-signing-identity-recommended)
- [4. Build and install](#4-build-and-install)
- [5. Grant the three permissions](#5-grant-the-three-permissions)
- [6. Your first dictation](#6-your-first-dictation)
- [7. Check the install](#7-check-the-install)
- [8. Make it yours](#8-make-it-yours)
- [Updating](#updating) · [Uninstalling](#uninstalling) · [Troubleshooting](#troubleshooting)

---

## 1. Check your Mac can run it

```sh
sw_vers -productVersion     # must be 27.0 or later (macOS Tahoe)
uname -m                    # must print: arm64  (Apple Silicon — Intel Macs are not supported)
df -h ~ | tail -1           # keep ~3 GB free for English, ~7 GB for all languages
swift --version             # if this fails, do step 1b
```

**1b. Install the Command Line Tools** (Xcode is *not* needed, ~1 GB):

```sh
xcode-select --install
```

Click through the installer, then re-run `swift --version`; it must print Swift 6.x. If you do have Xcode installed and
`swift` still isn't found, point the toolchain at it once: `sudo xcode-select -s /Applications/Xcode.app`.

You also need a microphone (the built-in one is fine) and, only for the optional **Prompt** / **Writing** /
**Smart Rewrite** modes, Apple Intelligence turned on in System Settings.

## 2. Get the code

**Option A — HTTPS (nothing to set up, recommended if you only want to use the app):**

```sh
git clone https://github.com/tejasnirala/voice-flow.git
cd voice-flow
```

**Option B — SSH (if you will push commits back).** You need an SSH key on this Mac and that key registered on GitHub.
Skip the first command if `~/.ssh/id_ed25519.pub` already exists:

```sh
ssh-keygen -t ed25519 -C "you@example.com" -f ~/.ssh/id_ed25519   # press Enter for a passphrase or type one
eval "$(ssh-agent -s)"
ssh-add --apple-use-keychain ~/.ssh/id_ed25519                    # remembers the passphrase in the Keychain
pbcopy < ~/.ssh/id_ed25519.pub                                    # public key now in your clipboard
```

Paste it at **github.com → Settings → SSH and GPG keys → New SSH key**, then verify and clone:

```sh
ssh -T git@github.com        # expect: "Hi <username>! You've successfully authenticated…"
git clone git@github.com:tejasnirala/voice-flow.git
cd voice-flow
```

Never share `~/.ssh/id_ed25519` (the private key); only the `.pub` file goes to GitHub.

## 3. Create a signing identity (recommended)

macOS ties the Microphone, Input Monitoring and Accessibility grants to the app's **code signature**. Without an identity
of your own, the build is signed ad hoc and its signature changes on every rebuild — so macOS forgets the permissions and
asks again after each rebuild, sometimes listing VoiceFlow twice in System Settings. One self-signed certificate fixes
that permanently. It takes a minute and is needed once per Mac.

1. Open Keychain Access:
   ```sh
   open -a "Keychain Access"
   ```
2. Menu bar → **Keychain Access → Certificate Assistant → Create a Certificate…**
3. Fill in:
   - **Name:** `VoiceFlow Dev`
   - **Identity Type:** Self Signed Root
   - **Certificate Type:** Code Signing
   - leave *Let me override defaults* unchecked
4. **Create → Continue → Done.**
5. Confirm the build script will find it:
   ```sh
   security find-identity -p codesigning | grep "VoiceFlow Dev"
   ```
   The line ends with `(CSSMERR_TP_NOT_TRUSTED)`. That is expected for a self-signed certificate and does not matter for
   signing a local build.

`scripts/build-app.sh` picks the identity up automatically. Using a different name? Export it before building:
`export VOICEFLOW_SIGN_IDENTITY="My Identity"`. Skipping this step entirely still works — the app is signed ad hoc and
you may have to re-grant permissions after future rebuilds.

## 4. Build and install

One command downloads the speech runtime and the English model, builds a release binary, runs the test suite and installs
the app into `~/Applications`:

```sh
scripts/install.sh --with-models
```

Add the other languages (German, Hindi, Hinglish — 3.4 GB more) in the same run if you want them:

```sh
scripts/install.sh --with-models --with-languages
```

<details>
<summary>What that command actually does</summary>

1. `scripts/fetch-deps.sh` — downloads the prebuilt whisper.cpp xcframework into `Vendor/` and checks its SHA-256.
2. `scripts/fetch-models.sh` — downloads the models into
   `~/Library/Application Support/VoiceFlow/models/whisper/`, each verified against Hugging Face's SHA-256.
3. `scripts/build-app.sh` — release build, assembles `VoiceFlow.app`, signs it with your identity.
4. `scripts/test.sh` — 170 unit tests; the install stops if any fail.
5. Copies the bundle to `~/Applications/VoiceFlow.app` and launches it.

Run the steps separately if you prefer, or if a download was interrupted — `fetch-models.sh` resumes and re-verifies.
Use `--applications` to install into `/Applications` instead (asks for your password), `--no-launch` to not start it.
</details>

The menu bar now shows a **microphone icon**. That is the whole app — there is no Dock icon.

**Only English, plus Hindi/Hinglish but not German** (skips the 2.2 GB German model; German then falls back to the Hindi
model, see [README → Languages](../README.md#languages)):

```sh
scripts/fetch-models.sh whisper large-v3-turbo-q8_0
scripts/fetch-models.sh whisper-coreml large-v3-turbo
```

## 5. Grant the three permissions

VoiceFlow needs exactly three, and macOS grants none of them silently:

| Permission | Why | When |
|---|---|---|
| **Microphone** | to hear you | asked automatically at your first dictation |
| **Input Monitoring** | to notice that you are holding ⌥ | you must enable it by hand |
| **Accessibility** | to paste the text into the app you were typing in | you must enable it by hand |

Easiest route: menu bar icon → **Open VoiceFlow…** → the **Home** page lists what is missing with a button for each.

By hand, these commands open the exact System Settings panes — click **+**, choose `~/Applications/VoiceFlow.app`, and
make sure its switch is on:

```sh
open "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"     # Input Monitoring
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"   # Accessibility
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"      # Microphone
```

If an older entry from `build/VoiceFlow.app` is listed, select it and remove it with **–** before adding the installed
copy. After changing these switches, restart the app so it picks them up:

```sh
osascript -e 'tell application id "local.voiceflow.VoiceFlow" to quit'; sleep 1; open ~/Applications/VoiceFlow.app
```

## 6. Your first dictation

1. Open TextEdit (or any editor) and click where the text should appear.
2. Hold **⌥ (Option)**, say a sentence, then release the key.
3. The pill at the bottom of the screen shows your input level; the text is pasted a moment after you release.

The **very first** dictation takes ~15–20 s extra: macOS compiles whisper.cpp's Metal shaders and the Neural Engine
encoder once and caches them. Every dictation after that is 0.6–0.9 s for a short sentence.

Worth knowing right away:

- **Double-tap ⌥** to record hands-free (no holding); tap **⌥** again to finish.
- **Esc** cancels a recording and pastes nothing.
- **⌥Space** is a fallback trigger if holding ⌥ does not suit you.
- **⌃⇧L** switches the dictation language; **auto-detect** is the default.
- Drag the pill anywhere — it stays where you put it.

## 7. Check the install

```sh
~/Applications/VoiceFlow.app/Contents/MacOS/VoiceFlow --diagnostics
```

This prints (and the menu's **Copy Diagnostics** copies) the version, macOS version and RAM, the speech model and whether
its Neural Engine encoder is installed, whether the on-device rewrite model is available, the state of all three
permissions, your settings, and the recent log lines. It contains no transcripts — the logs never hold what you said.

A healthy report has the model line ending in *installed*, the encoder *installed*, and all three permissions *allowed*.

## 8. Make it yours

- **Open at Login** — menu bar → Open at Login, so it is running whenever you are.
- **Mode** — Clean is the default; Developer writes `package.json`, `--save-dev`, `user_id`, `kubectl get pods`
  correctly. See the mode table in the [README](../README.md#text-modes).
- **Mode per app** — window → **Apps**: e.g. VS Code → Developer, Slack → Clean, ChatGPT → Prompt.
- **Language per app** — same page, e.g. WhatsApp → Hinglish. Faster and more reliable than auto-detect for very short
  sentences.
- **Your dictionary** — window → **Dictionary**: your own terms and spoken→written replacements
  (`~/Library/Application Support/VoiceFlow/dictionary.json`).

## Updating

```sh
cd voice-flow && git pull && scripts/install.sh
```

Models are kept; `--with-models` / `--with-languages` only re-verify what is already there.

## Uninstalling

```sh
scripts/uninstall.sh            # removes the app, keeps models, settings and dictionary
scripts/uninstall.sh --purge    # also deletes ~/Library/Application Support/VoiceFlow (models included, after asking)
```

Then remove VoiceFlow from System Settings → Privacy & Security (Microphone, Accessibility, Input Monitoring) and from
Login Items if it is still listed.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `✗ swift not found` | Step 1b: `xcode-select --install` |
| `Vendor/whisper.xcframework missing` | `scripts/fetch-deps.sh` (the installer does this for you) |
| `! speech model not installed yet` | `scripts/fetch-models.sh whisper medium.en-q8_0 && scripts/fetch-models.sh whisper-coreml medium.en` |
| A download stopped or `checksum mismatch` | Re-run the same `fetch-models.sh` command — it resumes and re-verifies |
| Holding ⌥ does nothing | Input Monitoring (step 5), then restart the app. Check the switch is on for `~/Applications/VoiceFlow.app`, not an old `build/` entry |
| The menu shows the dictation but nothing is pasted | Accessibility (step 5), then restart the app |
| macOS says the app "cannot be verified" | Expected: the build is signed locally, not notarized. Right-click the app → **Open** → Open |
| Two VoiceFlow entries in Spotlight or System Settings | A development build got registered. `scripts/install.sh` unregisters it; remove the stale permission entry with **–** |
| The first dictation takes ~20 s | Metal shaders and the Core ML encoder compile once per binary, then it is cached |
| Hindi comes out as English | Very short utterances are hard to detect. Press **⌃⇧L** to fix the language, or set it per app (step 8) |
| German comes out as English | Detection is acoustic — a non-native accent reads as English. Fix the language with **⌃⇧L** |
| Prompt / Writing behave like Clean | They need Apple Intelligence (English or German only; there is no Hindi in Apple's on-device model) |
| AirPods miss the first word | They start capturing ~0.5 s after the key press; the pill turns red when audio is actually flowing |

Still stuck? Run step 7, then open an issue with that report (it is safe to paste) —
[SECURITY.md](../SECURITY.md) for anything privacy-related instead.
