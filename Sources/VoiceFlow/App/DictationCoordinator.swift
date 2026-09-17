import AppKit
import VoiceFlowCore

/// Connects hardware/OS events to the `PipelineStateMachine` and performs the side effects of each
/// accepted transition: hotkey → recording → local STT → paste into the focused app.
@MainActor
final class DictationCoordinator {
    private(set) var machine = PipelineStateMachine()
    private let hotkeys = GlobalHotkeyManager()
    private let recorder = AudioRecorder()
    private var settings: Settings

    /// Per-recording measurements, set when recording starts.
    private var pressUptimeNs: UInt64 = 0
    private var cpuAtStart = 0.0
    private var footprintAtStartMB = 0.0

    /// Audio waiting for transcription. Kept after a transcription failure so it can be retried; otherwise
    /// released as soon as the dictation ends. Memory only.
    private var pendingAudio: [Float]?
    private var pendingSpeechSeconds = 0.0

    // MARK: Speech-to-text state
    private var speechEngine: WhisperEngine?
    private var speechEngineKey: String?
    /// Model load started when recording begins, so the model is ready (or nearly) at release.
    private var prepareTask: Task<Void, Error>?
    private var unloadWork: DispatchWorkItem?

    // MARK: Insertion state
    private let inserter = TextInserter()
    /// App in front when the hotkey was pressed; the transcript is only pasted into this app.
    private var dictationApp: NSRunningApplication?
    private var releaseUptimeNs: UInt64 = 0
    /// Measurement mode turns this off so automated runs never type into whatever app is in front.
    var insertionEnabled = true

    /// Most recent transcript, kept in memory only (shown in the menu, cleared on quit).
    private(set) var lastTranscript: String?
    /// Called when the STT model status or the last transcript changes.
    var onSpeechInfoChange: ((STTModelStatus, String?) -> Void)?
    private(set) var modelStatus: STTModelStatus = .missing

    /// Called after every accepted transition, before its side effects run.
    var onStateChange: ((PipelineState) -> Void)?
    /// Called when a dictation ends: the pipeline returns to idle or error from an active state (measurement mode).
    var onDictationComplete: (() -> Void)?

    init(settings: Settings) {
        self.settings = settings
    }

    /// Measurement hook: whether the stopped audio engine is kept between recordings.
    var reuseAudioEngine: Bool {
        get { recorder.reuseEngine }
        set { recorder.reuseEngine = newValue }
    }

    func start() {
        refreshModelStatus()
        hotkeys.onHotkey = { [weak self] action, phase, latencyMs in
            self?.handleHotkey(action, phase, latencyMs: latencyMs)
        }
        recorder.onLimitReached = { [weak self] in
            guard let self, self.machine.state == .recording else { return }
            Log.audio.notice("max recording duration reached (\(self.settings.maxRecordingSeconds, format: .fixed(precision: 0), privacy: .public) s)")
            self.finishRecording(event: .recordingLimitReached)
        }
        recorder.onDeviceChanged = { [weak self] in
            guard let self, self.machine.state == .recording else { return }
            // Keep what was captured rather than losing it; the next recording uses the new device.
            Log.audio.error("input device changed during recording; stopping with the audio captured so far")
            self.finishRecording(event: .hotkeyReleased)
        }

        let hotkey = settings.hotkey
        do {
            try hotkeys.register(.dictation, keyCode: hotkey.keyCode, carbonModifiers: hotkey.carbonModifiers)
            Log.hotkey.notice("registered \(hotkey.displayName, privacy: .public)")
        } catch {
            let reason = error.isAlreadyTaken
                ? "\(hotkey.displayName) is already used by another app"
                : "\(hotkey.displayName) couldn't be registered (OSStatus \(error.status))"
            Log.hotkey.error("registration failed: \(reason, privacy: .public)")
            send(.failed(PipelineFailure(stage: .hotkey, message: reason)))
        }
    }

    func updateSettings(_ settings: Settings) {
        self.settings = settings
        refreshModelStatus()
    }

    func dismissError() {
        send(.errorDismissed)
    }

    func retryTranscription() {
        send(.retryTranscriptionRequested)
    }

    /// Frees the model synchronously. Called on quit (ggml's Metal backend asserts if a context outlives exit).
    func shutdown() {
        unloadWork?.cancel()
        speechEngine?.unload()
    }

    private func refreshModelStatus() {
        modelStatus = STTModelManager.quickStatus(for: settings.sttModel)
        if modelStatus != .installed {
            Log.speech.error("model \(self.settings.sttModel.id, privacy: .public) status: \(String(describing: self.modelStatus), privacy: .public)")
        }
        onSpeechInfoChange?(modelStatus, lastTranscript)
    }

    /// Starts a recording without the hotkey (measurement mode). Returns false if it couldn't start.
    func startRecordingProgrammatically() -> Bool {
        pressUptimeNs = DispatchTime.now().uptimeNanoseconds
        dictationApp = NSWorkspace.shared.frontmostApplication
        send(.hotkeyPressed)
        return machine.state == .recording
    }

    func stopRecordingProgrammatically() {
        guard machine.state == .recording else { return }
        finishRecording(event: .hotkeyReleased)
    }

    // MARK: - Hotkey

    /// Hotkey events are normally dispatched within ~0.1 ms. While VoiceFlow's own status menu is open, macOS
    /// holds them until the menu closes, then delivers press and release together (observed: 6.4 s late).
    /// Starting a recording from such a stale press would capture nothing useful, so it's ignored.
    static let staleHotkeyThresholdMs = 500.0

    private func handleHotkey(_ action: GlobalHotkeyManager.Action, _ phase: GlobalHotkeyManager.Phase, latencyMs: Double) {
        switch (action, phase) {
        case (.dictation, .pressed) where latencyMs > Self.staleHotkeyThresholdMs:
            Log.hotkey.error("ignored stale press, dispatch latency \(latencyMs, format: .fixed(precision: 0), privacy: .public) ms (menu open?)")
        case (.dictation, .pressed):
            Log.hotkey.notice("pressed, dispatch latency \(latencyMs, format: .fixed(precision: 2), privacy: .public) ms")
            pressUptimeNs = DispatchTime.now().uptimeNanoseconds - UInt64(max(0, latencyMs) * 1_000_000)
            dictationApp = NSWorkspace.shared.frontmostApplication
            send(.hotkeyPressed)
        case (.dictation, .released):
            Log.hotkey.notice("released, dispatch latency \(latencyMs, format: .fixed(precision: 2), privacy: .public) ms")
            if machine.state == .recording {
                finishRecording(event: .hotkeyReleased)
            } else {
                send(.hotkeyReleased) // rejected by the state machine; logged as ignored
            }
        case (.cancel, .pressed), (.cancelWithOption, .pressed):
            send(.cancelRequested)
        case (.cancel, .released), (.cancelWithOption, .released):
            break
        }
    }

    // MARK: - State machine

    private func send(_ event: PipelineEvent) {
        let previous = machine.state
        guard let next = machine.handle(event) else {
            Log.pipeline.info("ignored \(String(describing: event), privacy: .public) in \(Self.name(previous), privacy: .public)")
            return
        }
        Log.pipeline.notice("\(Self.name(previous), privacy: .public) → \(Self.name(next), privacy: .public)")
        onStateChange?(next)
        runEffects(from: previous, to: next, event: event)
        // Use this transition's own result: effects may already have sent nested events (e.g. inserting → idle),
        // and those report their own completion.
        if previous.isActive, !next.isActive { onDictationComplete?() }
    }

    private func runEffects(from previous: PipelineState, to next: PipelineState, event: PipelineEvent) {
        if next == .recording, previous != .recording {
            beginRecording()
            return
        }
        if previous == .recording, next != .recording {
            hotkeys.unregister(.cancel)
            hotkeys.unregister(.cancelWithOption)
            if recorder.isRecording { // cancel or failure: the audio isn't kept
                recorder.cancel()
                Log.audio.notice("recording discarded (\(String(describing: event), privacy: .public))")
            }
        }

        switch next {
        case .transcribing:
            transcribePendingAudio()
        case .inserting:
            insertLastTranscript()
        case .idle:
            pendingAudio = nil
        case .error(let failure) where failure.recovery != .retryTranscription:
            pendingAudio = nil
        default:
            break
        }
    }

    // MARK: - Recording

    private func beginRecording() {
        switch PermissionManager.microphone {
        case .authorized:
            break
        case .notDetermined:
            PermissionManager.requestMicrophone { granted in
                Log.audio.notice("microphone permission \(granted ? "granted" : "denied", privacy: .public)")
            }
            send(.failed(PipelineFailure(stage: .recording,
                                         message: "Allow microphone access in the prompt, then hold \(settings.hotkey.displayName) again")))
            return
        case .denied:
            send(.failed(PipelineFailure(stage: .recording,
                                         message: "Microphone access is off for VoiceFlow",
                                         recovery: .openMicrophoneSettings)))
            return
        }

        unloadWork?.cancel()
        prepareSpeechEngine()
        cpuAtStart = ResourceUsage.cpuSeconds
        footprintAtStartMB = ResourceUsage.footprintMB
        do {
            let metrics = try recorder.start(maxSeconds: settings.maxRecordingSeconds)
            let sincePressMs = Double(DispatchTime.now().uptimeNanoseconds - pressUptimeNs) / 1_000_000
            Log.audio.notice("""
                recording started: device "\(metrics.deviceName, privacy: .public)" \
                \(metrics.deviceSampleRate, format: .fixed(precision: 0), privacy: .public) Hz \
                \(metrics.deviceChannels, privacy: .public) ch; start() \(metrics.startCallMs, format: .fixed(precision: 1), privacy: .public) ms, \
                press → running \(sincePressMs, format: .fixed(precision: 1), privacy: .public) ms
                """)
        } catch {
            Log.audio.error("recording failed to start: \(error.localizedDescription, privacy: .public)")
            send(.failed(PipelineFailure(stage: .recording, message: error.localizedDescription)))
            return
        }
        registerCancelKeys()
    }

    /// Stops capture, measures the recording, and decides whether there's anything to transcribe.
    private func finishRecording(event: PipelineEvent) {
        let firstBuffer = recorder.firstBufferUptimeNs
        let samples = recorder.stop()
        let analysis = RecordingGate.analyze(samples, sampleRate: AudioRecorder.sampleRate)
        let verdict = RecordingGate.verdict(for: analysis)
        let firstBufferMs = firstBuffer.map { Double($0 - pressUptimeNs) / 1_000_000 } ?? -1

        Log.audio.notice("""
            recording stopped: \(analysis.durationSeconds, format: .fixed(precision: 2), privacy: .public) s, \
            press → first buffer \(firstBufferMs, format: .fixed(precision: 1), privacy: .public) ms, \
            leading digital silence \(analysis.leadingSilenceSeconds * 1000, format: .fixed(precision: 0), privacy: .public) ms, \
            peak \(analysis.peakFrameDBFS, format: .fixed(precision: 1), privacy: .public) dBFS, \
            speech \(analysis.speechSeconds, format: .fixed(precision: 2), privacy: .public) s, \
            verdict \(String(describing: verdict), privacy: .public), \
            CPU \((ResourceUsage.cpuSeconds - self.cpuAtStart) * 1000, format: .fixed(precision: 0), privacy: .public) ms, \
            footprint \(self.footprintAtStartMB, format: .fixed(precision: 1), privacy: .public) → \(ResourceUsage.footprintMB, format: .fixed(precision: 1), privacy: .public) MB
            """)

        if settings.saveRecordingsForDebugging, !samples.isEmpty {
            do {
                let url = try DebugRecordingWriter.write(samples, sampleRate: AudioRecorder.sampleRate)
                Log.audio.notice("debug recording saved: \(url.lastPathComponent, privacy: .public)")
            } catch {
                Log.audio.error("debug recording not saved: \(error.localizedDescription, privacy: .public)")
            }
        }

        if verdict == .keep {
            pendingAudio = samples
            pendingSpeechSeconds = analysis.speechSeconds
            send(event)
        } else {
            send(.recordingDiscarded)
            scheduleUnload()
        }
    }

    // MARK: - Speech-to-text

    /// Returns the engine for the current settings, creating it if the model or prompt setting changed.
    private func currentSpeechEngine() -> WhisperEngine {
        let model = settings.sttModel
        let key = "\(model.id)|\(settings.useVocabularyPrompt)"
        if let engine = speechEngine, speechEngineKey == key { return engine }
        speechEngine?.unload()
        let engine = WhisperEngine(model: model, modelURL: STTModelManager.url(for: model),
                                   prompt: settings.useVocabularyPrompt ? STTModelManager.vocabularyPrompt() : nil)
        speechEngine = engine
        speechEngineKey = key
        return engine
    }

    /// Verifies and loads the model in the background while the user is still speaking.
    private func prepareSpeechEngine() {
        let engine = currentSpeechEngine()
        // Restart whenever the model isn't loaded, so an earlier failure (e.g. model missing, since installed)
        // isn't reused. Concurrent loads are safe: the engine serializes them and loads at most once.
        guard !engine.isLoaded else { return }
        let model = engine.model
        prepareTask = Task.detached(priority: .userInitiated) {
            let (status, hashed) = STTModelManager.verify(model)
            if hashed > 0 {
                Log.speech.notice("model verified (SHA-256) in \(hashed, format: .fixed(precision: 2), privacy: .public) s: \(String(describing: status), privacy: .public)")
            }
            guard status == .installed else { throw ModelUnavailable(status: status, model: model) }
            let start = DispatchTime.now().uptimeNanoseconds
            try engine.prepare()
            Log.speech.notice("model loaded in \(Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9, format: .fixed(precision: 2), privacy: .public) s (started at recording start)")
        }
    }

    struct ModelUnavailable: LocalizedError {
        let status: STTModelStatus
        let model: STTModel
        var errorDescription: String? {
            switch status {
            case .missing: "Speech model not installed. Run: \(model.installCommand)"
            case .corrupted(let reason): "Speech model file is damaged (\(reason)). Reinstall: \(model.installCommand)"
            case .incompatible(let reason): "Speech model can't be used (\(reason))"
            case .installed: "Speech model unavailable"
            }
        }
    }

    private func transcribePendingAudio() {
        guard let audio = pendingAudio else {
            send(.transcriptionEmpty)
            return
        }
        let engine = currentSpeechEngine()
        if !engine.isLoaded { prepareSpeechEngine() }
        let preparation = prepareTask
        let speechSeconds = pendingSpeechSeconds
        let releasedAt = DispatchTime.now().uptimeNanoseconds
        releaseUptimeNs = releasedAt
        let cpuBefore = ResourceUsage.cpuSeconds

        Task { [weak self] in
            let outcome: Result<TranscriptionResult, Error> = await Task.detached(priority: .userInitiated) {
                do {
                    try await preparation?.value
                    return .success(try engine.transcribe(audio))
                } catch {
                    return .failure(error)
                }
            }.value
            self?.finishTranscription(outcome, speechSeconds: speechSeconds, releasedAt: releasedAt, cpuBefore: cpuBefore)
        }
    }

    private func finishTranscription(_ outcome: Result<TranscriptionResult, Error>, speechSeconds: Double,
                                     releasedAt: UInt64, cpuBefore: Double) {
        prepareTask = nil
        refreshModelStatus()
        guard machine.state == .transcribing else {
            Log.speech.notice("transcription result discarded (state changed)")
            return
        }
        switch outcome {
        case .failure(let error):
            Log.speech.error("transcription failed: \(error.localizedDescription, privacy: .public)")
            send(.failed(PipelineFailure(stage: .transcription, message: error.localizedDescription, recovery: .retryTranscription)))
        case .success(var result):
            let cleaned = TranscriptGuard.clean(result.text, speechSeconds: speechSeconds)
            result.guardFlags = cleaned.flags
            result.text = cleaned.text
            let totalMs = Double(DispatchTime.now().uptimeNanoseconds - releasedAt) / 1_000_000
            let words = result.text.split(whereSeparator: \.isWhitespace).count
            Log.speech.notice("""
                stt: audio \(result.audioSeconds, format: .fixed(precision: 2), privacy: .public) s, \
                \(result.chunkCount, privacy: .public) chunk(s) / \(result.transcribedAudioSeconds, format: .fixed(precision: 1), privacy: .public) s sent, \
                transcribe \(result.transcribeSeconds, format: .fixed(precision: 3), privacy: .public) s \
                (RTF \(result.transcribeSeconds / max(result.audioSeconds, 0.001), format: .fixed(precision: 3), privacy: .public)), \
                \(result.coldStart ? "cold" : "warm", privacy: .public), load in call \(result.loadSeconds, format: .fixed(precision: 2), privacy: .public) s, \
                waited for model \(result.waitedForModelSeconds, format: .fixed(precision: 2), privacy: .public) s, \
                release → text \(totalMs, format: .fixed(precision: 0), privacy: .public) ms, \
                \(words, privacy: .public) words, guard \(result.guardFlags.map(\.rawValue).sorted().joined(separator: ","), privacy: .public), \
                CPU \((ResourceUsage.cpuSeconds - cpuBefore) * 1000, format: .fixed(precision: 0), privacy: .public) ms, \
                footprint \(ResourceUsage.footprintMB, format: .fixed(precision: 0), privacy: .public) MB
                """)
            pendingAudio = nil
            scheduleUnload()
            if result.text.isEmpty {
                send(.transcriptionEmpty)
            } else {
                lastTranscript = result.text
                onSpeechInfoChange?(modelStatus, lastTranscript)
                send(.transcriptionSucceeded(needsProcessing: false))
            }
        }
    }

    // MARK: - Insertion

    private func insertLastTranscript() {
        guard let text = lastTranscript else {
            send(.insertionFinished)
            return
        }
        guard insertionEnabled else {
            Log.insertion.notice("insertion disabled (measurement mode)")
            send(.insertionFinished)
            return
        }
        let target = dictationApp
        inserter.insert(text, dictationApp: target) { [weak self] outcome, metrics, restored in
            guard let self else { return }
            if let restored {
                Log.insertion.notice("clipboard \(restored ? "restored" : "left as is (changed by the user after the paste)", privacy: .public)")
                return
            }
            let totalMs = Double(DispatchTime.now().uptimeNanoseconds - self.releaseUptimeNs) / 1_000_000
            let app = target?.bundleIdentifier ?? "unknown"
            switch outcome {
            case .pasted:
                Log.insertion.notice("""
                    pasted into \(app, privacy: .public): snapshot \(metrics.snapshotItems, privacy: .public) items \
                    \(metrics.snapshotBytes / 1024, privacy: .public) KB in \(metrics.snapshotMs, format: .fixed(precision: 1), privacy: .public) ms, \
                    write \(metrics.writeMs, format: .fixed(precision: 1), privacy: .public) ms, ⌘V \(metrics.pasteEventMs, format: .fixed(precision: 1), privacy: .public) ms; \
                    release → pasted \(totalMs, format: .fixed(precision: 0), privacy: .public) ms
                    """)
                self.send(.insertionFinished)
            case .leftOnClipboard(let reason):
                Log.insertion.notice("not pasted (\(String(describing: reason), privacy: .public)); transcript left on clipboard")
                self.send(.failed(PipelineFailure(
                    stage: .insertion, message: InsertionPolicy.message(for: reason),
                    recovery: reason == .accessibilityNotGranted ? .openAccessibilitySettings : nil)))
            }
        }
    }

    /// One-shot timer (not polling): frees ~1 GB of model memory after the configured idle time.
    private func scheduleUnload() {
        unloadWork?.cancel()
        guard let engine = speechEngine else { return }
        let delay = settings.sttUnloadAfterSeconds
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.machine.state.isActive, engine.isLoaded else { return }
            DispatchQueue.global(qos: .utility).async {
                let before = ResourceUsage.footprintMB
                engine.unload()
                // ~170 MB stays allocated inside whisper.cpp/ggml after whisper_free (not allocator caching:
                // malloc_zone_pressure_relief frees 0 MB). See PERFORMANCE.md §3.4.
                Log.speech.notice("""
                    model unloaded after \(delay, format: .fixed(precision: 0), privacy: .public) s idle: footprint \
                    \(before, format: .fixed(precision: 0), privacy: .public) → \(ResourceUsage.footprintMB, format: .fixed(precision: 0), privacy: .public) MB
                    """)
            }
        }
        unloadWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func registerCancelKeys() {
        let esc = UInt32(53), option = UInt32(0x0800)
        do {
            try hotkeys.register(.cancel, keyCode: esc, carbonModifiers: 0)
            try hotkeys.register(.cancelWithOption, keyCode: esc, carbonModifiers: option)
        } catch {
            // Not fatal: dictation still works; only Esc-to-cancel is unavailable.
            Log.hotkey.error("Esc cancel registration failed (OSStatus \(error.status))")
        }
    }

    private static func name(_ state: PipelineState) -> String {
        switch state {
        case .error: "error"
        default: String(describing: state)
        }
    }
}
