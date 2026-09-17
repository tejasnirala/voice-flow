import Foundation
import VoiceFlowCore

/// Connects hardware/OS events to the `PipelineStateMachine` and performs the side effects of each
/// accepted transition. Phase 3: hotkey + audio recording. STT and insertion are attached in later phases.
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

    /// Audio waiting for transcription (Phase 4). Released as soon as it's no longer needed.
    private var pendingAudio: [Float]?

    /// Called after every accepted transition, before its side effects run.
    var onStateChange: ((PipelineState) -> Void)?
    /// Called when a recording ends (for measurement mode).
    var onRecordingFinished: (() -> Void)?

    init(settings: Settings) {
        self.settings = settings
    }

    /// Measurement hook: whether the stopped audio engine is kept between recordings.
    var reuseAudioEngine: Bool {
        get { recorder.reuseEngine }
        set { recorder.reuseEngine = newValue }
    }

    func start() {
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
    }

    func dismissError() {
        send(.errorDismissed)
    }

    /// Starts a recording without the hotkey (measurement mode). Returns false if it couldn't start.
    func startRecordingProgrammatically() -> Bool {
        pressUptimeNs = DispatchTime.now().uptimeNanoseconds
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
                onRecordingFinished?()
            }
        }

        switch next {
        case .transcribing:
            // Phase 3 stub: no STT yet. The audio would be transcribed here (Phase 4).
            pendingAudio = nil
            send(.transcriptionEmpty)
        case .idle, .error:
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

        onRecordingFinished?()
        if verdict == .keep {
            pendingAudio = samples
            send(event)
        } else {
            send(.recordingDiscarded)
        }
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
