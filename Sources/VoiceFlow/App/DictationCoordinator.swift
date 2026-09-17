import AppKit
import VoiceFlowCore

/// Connects hardware/OS events to the `PipelineStateMachine` and performs the side effects of each
/// accepted transition: hotkey → recording → local STT → paste into the focused app.
@MainActor
final class DictationCoordinator {
    private(set) var machine = PipelineStateMachine()
    private let hotkeys = GlobalHotkeyManager()
    private let modifierMonitor = ModifierKeyMonitor()
    private var gesture = ModifierKeyGesture()
    /// True only while a recording started by the ⌥ gesture is in progress; the gesture may finish or cancel only that.
    private var gestureOwnsRecording = false
    private var doubleTapWork: DispatchWorkItem?
    /// Which trigger is actually active (⌥ may fall back to the key combination without Input Monitoring).
    private(set) var activeTrigger: Settings.DictationTrigger = .hotkeyCombination
    var isHandsFree: Bool { gesture.isHandsFree && machine.state == .recording }
    /// Called when the active trigger, its warning, or hands-free mode changes (menu text).
    var onTriggerInfoChange: (() -> Void)?
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
    private var speechEngine: HelperSpeechEngine?
    private var speechEngineKey: String?
    /// Model load started when recording begins, so the model is ready (or nearly) at release.
    private var prepareTask: Task<Void, Error>?
    private var unloadWork: DispatchWorkItem?

    // MARK: Insertion state
    private let inserter = TextInserter()
    /// App in front when the hotkey was pressed (used when `Settings.pasteInto` is `.dictationApp`, and for logging).
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
    /// Recording is live: real (non-zero) audio is arriving, so speech from now on is captured.
    var onAudioFlowing: (() -> Void)?
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
        recorder.onAudioFlowing = { [weak self] in
            guard let self, self.machine.state == .recording else { return }
            let ms = Double(DispatchTime.now().uptimeNanoseconds - self.pressUptimeNs) / 1_000_000
            Log.audio.notice("audio flowing \(ms, format: .fixed(precision: 0), privacy: .public) ms after press")
            self.onAudioFlowing?()
        }
        recorder.onDeviceChanged = { [weak self] in
            guard let self, self.machine.state == .recording else { return }
            // Keep what was captured rather than losing it; the next recording uses the new device.
            Log.audio.error("input device changed during recording; stopping with the audio captured so far")
            self.finishRecording(event: .hotkeyReleased)
        }

        modifierMonitor.onEvent = { [weak self] event, latencyMs in
            self?.handleModifier(event, latencyMs: latencyMs)
        }
        activateTrigger()
    }

    /// Uses ⌥ alone when configured and Input Monitoring is granted; otherwise registers the key combination.
    func activateTrigger() {
        if settings.dictationTrigger == .option {
            if ModifierKeyMonitor.hasPermission, modifierMonitor.start() {
                if activeTrigger != .option {
                    hotkeys.unregister(.dictation)
                    hotkeyRegistered = false
                }
                activeTrigger = .option
                triggerWarning = nil
                Log.hotkey.notice("dictation trigger: ⌥ key (hold, double-tap for hands-free)")
                onTriggerInfoChange?()
                return
            }
            if !ModifierKeyMonitor.hasPermission { ModifierKeyMonitor.requestPermission() }
            triggerWarning = "⌥-key dictation needs Input Monitoring — using \(settings.hotkey.displayName) until allowed"
            Log.hotkey.error("⌥ trigger unavailable (Input Monitoring not granted); falling back to \(self.settings.hotkey.displayName, privacy: .public)")
        } else {
            modifierMonitor.stop()
            triggerWarning = nil
        }
        guard activeTrigger != .hotkeyCombination || !hotkeyRegistered else { onTriggerInfoChange?(); return }
        let hotkey = settings.hotkey
        do {
            try hotkeys.register(.dictation, keyCode: hotkey.keyCode, carbonModifiers: hotkey.carbonModifiers)
            hotkeyRegistered = true
            activeTrigger = .hotkeyCombination
            Log.hotkey.notice("registered \(hotkey.displayName, privacy: .public)")
        } catch {
            let reason = error.isAlreadyTaken
                ? "\(hotkey.displayName) is already used by another app"
                : "\(hotkey.displayName) couldn't be registered (OSStatus \(error.status))"
            Log.hotkey.error("registration failed: \(reason, privacy: .public)")
            send(.failed(PipelineFailure(stage: .hotkey, message: reason)))
        }
        onTriggerInfoChange?()
    }

    private var hotkeyRegistered = false
    private(set) var triggerWarning: String?

    /// Human-readable instruction for the idle menu line.
    var triggerInstructions: String {
        activeTrigger == .option
            ? "hold ⌥ to dictate, double-tap ⌥ for hands-free"
            : "hold \(settings.hotkey.displayName) to dictate"
    }

    // MARK: - ⌥ key gesture

    private func handleModifier(_ event: ModifierKeyMonitor.Event, latencyMs: Double) {
        guard activeTrigger == .option else { return }
        if event == .down, latencyMs > Self.staleHotkeyThresholdMs {
            Log.hotkey.error("ignored stale ⌥ press, latency \(latencyMs, format: .fixed(precision: 0), privacy: .public) ms")
            return
        }
        let input: ModifierKeyGesture.Input = switch event {
        case .down: .keyDown
        case .up: .keyUp
        case .chord: .chord
        }
        let eventTime = Double(DispatchTime.now().uptimeNanoseconds) / 1e9 - latencyMs / 1000
        if event != .chord || gestureOwnsRecording {
            Log.hotkey.info("⌥ \(String(describing: event), privacy: .public), latency \(latencyMs, format: .fixed(precision: 2), privacy: .public) ms")
        }
        perform(gesture.handle(input, at: eventTime), latencyMs: latencyMs)
    }

    private func perform(_ actions: [ModifierKeyGesture.Action], latencyMs: Double) {
        for action in actions {
            switch action {
            case .startRecording:
                guard machine.state == .idle || { if case .error = machine.state { return true } else { return false } }() else {
                    Log.hotkey.notice("⌥ press ignored: dictation already in progress (\(Self.name(self.machine.state), privacy: .public))")
                    continue
                }
                Log.hotkey.notice("⌥ down, dispatch latency \(latencyMs, format: .fixed(precision: 2), privacy: .public) ms")
                pressUptimeNs = DispatchTime.now().uptimeNanoseconds - UInt64(max(0, latencyMs) * 1_000_000)
                dictationApp = NSWorkspace.shared.frontmostApplication
                send(.hotkeyPressed)
                gestureOwnsRecording = machine.state == .recording
            case .finishRecording:
                guard gestureOwnsRecording, machine.state == .recording else { continue }
                finishRecording(event: .hotkeyReleased)
            case .cancelRecording:
                guard gestureOwnsRecording, machine.state == .recording else { continue }
                Log.hotkey.notice("⌥ tap or chord: recording discarded")
                send(.cancelRequested)
            case .enteredHandsFree:
                guard gestureOwnsRecording, machine.state == .recording else { continue }
                doubleTapWork?.cancel()
                Log.hotkey.notice("hands-free dictation on")
                onStateChange?(machine.state)
                onTriggerInfoChange?()
            case .scheduleDoubleTapTimeout(let seconds):
                doubleTapWork?.cancel()
                let work = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    let now = Double(DispatchTime.now().uptimeNanoseconds) / 1e9
                    self.perform(self.gesture.handle(.doubleTapTimeout, at: now), latencyMs: 0)
                }
                doubleTapWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
            }
        }
    }

    func updateSettings(_ settings: Settings) {
        let triggerChanged = settings.dictationTrigger != self.settings.dictationTrigger
        self.settings = settings
        refreshModelStatus()
        if triggerChanged || (settings.dictationTrigger == .option && activeTrigger != .option) { activateTrigger() }
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
        modifierMonitor.stop()
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
            // Esc, max duration, errors or the gesture itself ended the recording: start the gesture fresh.
            let wasHandsFree = gesture.isHandsFree
            gesture.reset()
            gestureOwnsRecording = false
            doubleTapWork?.cancel()
            if wasHandsFree { onTriggerInfoChange?() }
            if recorder.isRecording { // cancel or failure: the audio isn't kept
                recorder.cancel()
                Log.audio.notice("recording discarded (\(String(describing: event), privacy: .public))")
            }
        }

        switch next {
        case .transcribing:
            transcribePendingAudio()
        case .processing:
            rewriteLastTranscript()
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
        dictionary = UserDictionary.load(from: UserDictionary.fileURL(in: SettingsStore.applicationSupportDirectory()))
        prepareSpeechEngine()
        // Prewarm for the mode of the app in front now; the final mode is chosen for the app that receives the text.
        let startMode = TargetApp.detect(dictationApp ?? NSWorkspace.shared.frontmostApplication).resolve(settings).mode
        if startMode.usesModel(processing: settings.processingMode), let prompt = rewritePrompt(for: startMode) {
            OnDeviceRewriter.prewarm(prompt: prompt)
        }
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
        let analysis = RecordingGate.analyze(samples, sampleRate: STTAudio.sampleRate)
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
                let url = try DebugRecordingWriter.write(samples, sampleRate: STTAudio.sampleRate)
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

    /// The owner's dictionary (`dictionary.json`), re-read at each recording start so edits apply without a restart.
    private var dictionary: UserDictionary = .empty

    /// Returns the engine for the current settings, creating it if the model or speech prompt changed.
    private func currentSpeechEngine() -> HelperSpeechEngine {
        let model = settings.sttModel
        let prompt = settings.useVocabularyPrompt ? dictionary.speechPrompt(base: DeveloperVocabulary.prompt()) : nil
        let key = "\(model.id)|\(prompt ?? "")"
        if let engine = speechEngine, speechEngineKey == key { return engine }
        speechEngine?.unload()
        let engine = HelperSpeechEngine(model: model, modelURL: STTModelManager.url(for: model), prompt: prompt)
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
            let total = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9
            if let load = engine.lastLoad {
                Log.speech.notice("""
                    speech helper ready in \(total, format: .fixed(precision: 2), privacy: .public) s (started at recording start): \
                    launch \(load.launchSeconds * 1000, format: .fixed(precision: 0), privacy: .public) ms, \
                    model load \(load.loadSeconds, format: .fixed(precision: 2), privacy: .public) s, encoder: \(load.encoder, privacy: .public)
                    """)
            }
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
            let detectStart = DispatchTime.now().uptimeNanoseconds
            let receiver = settings.pasteInto == .currentApp ? NSWorkspace.shared.frontmostApplication : dictationApp
            let target = TargetApp.detect(receiver)
            let resolution = target.resolve(settings)
            let mode = resolution.mode
            let detectMs = Double(DispatchTime.now().uptimeNanoseconds - detectStart) / 1_000_000
            Log.pipeline.notice("""
                mode \(mode.rawValue, privacy: .public) (\(resolution.source.rawValue, privacy: .public)) for \(target.bundleID ?? "unknown", privacy: .public), \
                detected in \(detectMs, format: .fixed(precision: 2), privacy: .public) ms
                """)
            let prepared = TextProcessingPlan.prepare(result.text, mode: mode, dictionary: dictionary)
            if prepared.isEmpty {
                send(.transcriptionEmpty)
            } else {
                lastTranscript = prepared
                onSpeechInfoChange?(modelStatus, lastTranscript)
                rewriteMode = mode
                let wordCount = prepared.split(whereSeparator: \.isWhitespace).count
                let rewrite = mode.usesModel(processing: settings.processingMode, wordCount: wordCount) && rewritePrompt(for: mode) != nil
                    && OnDeviceRewriter.unavailableReason == nil
                send(.transcriptionSucceeded(needsProcessing: rewrite))
            }
        }
    }

    // MARK: - Model rewrite (Smart Mode for Clean/Developer; always for Prompt/Writing)

    /// Text mode of the transcript being processed (fixed at transcription time, so a menu change can't mix modes).
    private var rewriteMode: TextMode = .clean
    private var rewritePrompts: [String: RewritePrompt] = [:]

    private func rewritePrompt(for mode: TextMode) -> RewritePrompt? {
        guard let name = mode.promptName else { return nil }
        if let cached = rewritePrompts[name] { return cached }
        let prompt = RewritePrompt.bundled(name)
        rewritePrompts[name] = prompt
        return prompt
    }
    private lazy var vocabularyTerms: [String] = RewriteGuard.terms(fromVocabulary: DeveloperVocabulary.prompt())

    private func rewriteLastTranscript() {
        let mode = rewriteMode
        guard let prepared = lastTranscript, let prompt = rewritePrompt(for: mode) else {
            send(.processingFellBackToTranscript)
            return
        }
        let terms = vocabularyTerms + dictionary.protectedTerms
        let dictionary = dictionary
        let start = DispatchTime.now().uptimeNanoseconds
        Task { [weak self] in
            var rewrite: String?
            var failure: String?
            do {
                rewrite = try await OnDeviceRewriter.rewrite(prepared, prompt: prompt)
            } catch {
                failure = error.localizedDescription
            }
            guard let self, self.machine.state == .processing else { return }
            let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
            let (text, verdict) = TextProcessingPlan.finalText(prepared: prepared, rewrite: rewrite, terms: terms, mode: mode,
                                                               dictionary: dictionary)
            self.lastTranscript = text
            self.onSpeechInfoChange?(self.modelStatus, text)
            switch verdict {
            case .accept?:
                Log.speech.notice("\(mode.rawValue, privacy: .public) rewrite accepted in \(ms, format: .fixed(precision: 0), privacy: .public) ms")
                self.send(.processingSucceeded)
            case .reject(let reasons)?:
                Log.speech.notice("\(mode.rawValue, privacy: .public) rewrite rejected by guard (\(reasons.joined(separator: ", "), privacy: .public)) in \(ms, format: .fixed(precision: 0), privacy: .public) ms; using cleaned transcript")
                self.send(.processingFellBackToTranscript)
            case nil:
                Log.speech.error("\(mode.rawValue, privacy: .public) rewrite failed (\(failure ?? "unknown", privacy: .public)) after \(ms, format: .fixed(precision: 0), privacy: .public) ms; using cleaned transcript")
                self.send(.processingFellBackToTranscript)
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
        let started = dictationApp
        inserter.insert(text, dictationApp: started, target: settings.pasteInto) { [weak self] outcome, metrics, restored in
            guard let self else { return }
            if let restored {
                Log.insertion.notice("clipboard \(restored ? "restored" : "left as is (changed by the user after the paste)", privacy: .public)")
                return
            }
            let totalMs = Double(DispatchTime.now().uptimeNanoseconds - self.releaseUptimeNs) / 1_000_000
            let startedIn = started?.bundleIdentifier ?? "unknown"
            switch outcome {
            case .pasted(let pastedApp):
                let app = pastedApp ?? "unknown"
                let moved = app == startedIn ? "" : " (dictation started in \(startedIn))"
                Log.insertion.notice("""
                    pasted into \(app, privacy: .public)\(moved, privacy: .public): snapshot \(metrics.snapshotItems, privacy: .public) items \
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
                // The helper process exits, returning all model memory (whisper.cpp keeps ~190 MB after whisper_free
                // and leaks ~0.7 MB per load when run in-process: PERFORMANCE.md §3.8–3.9).
                engine.unload()
                Log.speech.notice("speech helper stopped after \(delay, format: .fixed(precision: 0), privacy: .public) s idle; app footprint \(ResourceUsage.footprintMB, format: .fixed(precision: 0), privacy: .public) MB")
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
