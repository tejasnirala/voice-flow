# Audio architecture

## Decision: AVAudioEngine input node tap (in-memory)

| Option | Pros | Cons |
|---|---|---|
| **AVAudioEngine** | Few lines of code. Handles device format. Built-in `AVAudioConverter` resampling | Engine start latency unknown on this machine (measure in Phase 3). Default-device changes need handling |
| Core Audio AUHAL (AudioUnit) | Lowest level, lowest overhead, precise start control | Much more code: device selection, format negotiation, render callback |
| AVCaptureSession | Device selection API | Designed for capture pipelines, heavier |
| AVAudioRecorder | Simplest | Writes a file to disk (spec: avoid disk I/O) |

Start with AVAudioEngine. Drop to AUHAL only if Phase 3 measures recording-start latency long
enough to clip the first word.

## Flow
1. Hotkey down → `engine.inputNode.installTap(bufferSize: 1024, format: nativeFormat)` → `engine.start()`.
2. Tap callback: convert to 16 kHz mono Float32 with a reused `AVAudioConverter` and append to a
   preallocated `[Float]` (capacity ~30 s = 480 k samples ≈ 1.8 MB).
3. Hotkey up → `engine.stop()` and remove the tap. The mic indicator turns off immediately.
4. Silence gate: duration < ~0.3 s or RMS below threshold → stop, no STT (spec §21).
5. Hand the samples to STT, then drop the buffer. **Nothing touches disk.**

## Latency considerations to measure (Phase 3)
- Engine start time per device. Built-in mic expected fastest. The iPhone Continuity mic is
  currently the system default. AirPods need a Bluetooth profile switch.
- `engine.prepare()` at app launch vs on key down: prepare may pre-allocate without turning on the
  mic. Measure whether it helps, and whether it affects idle CPU/RAM.
- Pre-roll: if start latency clips the first syllable, keep a short ring buffer only while the
  hotkey is held. **Never record continuously.**
