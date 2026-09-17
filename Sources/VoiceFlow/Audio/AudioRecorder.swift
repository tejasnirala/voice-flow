import AVFoundation
import os

/// Captures the default input device while dictating: AVAudioEngine input tap → one `AVAudioConverter` step →
/// 16 kHz mono Float32 accumulated in memory. Nothing is written to disk.
///
/// The engine is created on the first recording and fully stopped between recordings, so the microphone
/// (and its orange indicator) is only active while the hotkey is held.
@MainActor
final class AudioRecorder {
    static let sampleRate = 16_000.0

    struct StartMetrics {
        let deviceName: String
        let deviceSampleRate: Double
        let deviceChannels: Int
        /// Time spent in engine setup + `start()`.
        let startCallMs: Double
    }

    enum RecorderError: LocalizedError {
        case noInputDevice
        case unsupportedFormat
        case engineFailed(Error)

        var errorDescription: String? {
            switch self {
            case .noInputDevice: "No microphone is available"
            case .unsupportedFormat: "The microphone's audio format isn't supported"
            case .engineFailed(let error): "The microphone couldn't start (\(error.localizedDescription))"
            }
        }
    }

    /// Called once when the recording reaches its maximum duration.
    var onLimitReached: (() -> Void)?
    /// Called if the input device changes while recording (e.g. AirPods connect). Audio captured so far is kept.
    var onDeviceChanged: (() -> Void)?

    private var engine: AVAudioEngine?
    private var sink: CaptureSink?
    private var configurationObserver: NSObjectProtocol?

    var isRecording: Bool { sink != nil }

    /// Monotonic time of the first delivered audio buffer of the current recording, if any.
    var firstBufferUptimeNs: UInt64? { sink?.firstBufferUptimeNs }

    func start(maxSeconds: Double) throws(RecorderError) -> StartMetrics {
        let begin = DispatchTime.now().uptimeNanoseconds
        let engine = self.engine ?? AVAudioEngine()
        self.engine = engine
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw .noInputDevice }
        guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Self.sampleRate, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: format, to: target) else { throw .unsupportedFormat }
        converter.downmix = true

        let sink = CaptureSink(converter: converter, target: target, inputSampleRate: format.sampleRate,
                               maxSamples: Int(maxSeconds * Self.sampleRate)) { [weak self] in
            DispatchQueue.main.async { self?.onLimitReached?() }
        }

        do {
            if #available(macOS 27.0, *) {
                try input.installAudioTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                    sink.consume(AVAudioPCMBuffer(copying: buffer))
                }
            } else {
                input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                    sink.consume(buffer)
                }
            }
            engine.prepare()
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw .engineFailed(error)
        }

        self.sink = sink
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onDeviceChanged?()
                self?.resetEngine()
            }
        }

        let device = AVCaptureDevice.default(for: .audio)
        return StartMetrics(
            deviceName: device?.localizedName ?? "unknown",
            deviceSampleRate: format.sampleRate,
            deviceChannels: Int(format.channelCount),
            startCallMs: Double(DispatchTime.now().uptimeNanoseconds - begin) / 1_000_000
        )
    }

    /// Stops capture and returns the recorded samples (16 kHz mono).
    func stop() -> [Float] {
        guard let sink else { return [] }
        teardown()
        return sink.takeSamples()
    }

    /// Stops capture and discards the audio.
    func cancel() {
        guard sink != nil else { return }
        teardown()
    }

    private func teardown() {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            // stop() releases the input device (the microphone indicator turns off). The stopped engine is kept
            // only if `reuseEngine` is set; see PERFORMANCE.md §4 for the measured trade-off.
            engine.stop()
            if !reuseEngine { self.engine = nil }
        }
        sink = nil
    }

    /// Keep the stopped AVAudioEngine between recordings (faster start) instead of rebuilding it.
    var reuseEngine = true

    /// Drops the engine so the next recording builds a fresh graph (after an input-device change).
    func resetEngine() {
        guard sink == nil else { return }
        engine = nil
    }
}

/// Receives buffers on the audio thread. The lock guards the accumulated samples, which the main actor
/// takes when recording stops.
private final class CaptureSink: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let target: AVAudioFormat
    private let ratio: Double
    private let maxSamples: Int
    private let onLimitReached: @Sendable () -> Void
    private let lock = OSAllocatedUnfairLock()
    private var samples: [Float] = []
    private var limitSignalled = false
    private var firstBufferNs: UInt64?

    var firstBufferUptimeNs: UInt64? { lock.withLockUnchecked { firstBufferNs } }

    init(converter: AVAudioConverter, target: AVAudioFormat, inputSampleRate: Double, maxSamples: Int,
         onLimitReached: @escaping @Sendable () -> Void) {
        self.converter = converter
        self.target = target
        ratio = target.sampleRate / inputSampleRate
        self.maxSamples = maxSamples
        self.onLimitReached = onLimitReached
        samples.reserveCapacity(min(maxSamples, Int(target.sampleRate * 30)))
    }

    func consume(_ buffer: AVAudioPCMBuffer) {
        let arrival = DispatchTime.now().uptimeNanoseconds
        lock.withLockUnchecked { if firstBufferNs == nil { firstBufferNs = arrival } }
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
        var supplied = false
        _ = converter.convert(to: output, error: nil) { _, status in
            if supplied { status.pointee = .noDataNow; return nil }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        guard output.frameLength > 0, let channel = output.floatChannelData?[0] else { return }
        let chunk = UnsafeBufferPointer(start: channel, count: Int(output.frameLength))

        // The closure runs synchronously under the lock, so capturing the non-Sendable buffer pointer is safe.
        let reachedLimit = lock.withLockUnchecked { () -> Bool in
            let room = maxSamples - samples.count
            guard room > 0 else { return false }
            samples.append(contentsOf: chunk.prefix(room))
            guard samples.count >= maxSamples, !limitSignalled else { return false }
            limitSignalled = true
            return true
        }
        if reachedLimit { onLimitReached() }
    }

    func takeSamples() -> [Float] {
        lock.withLockUnchecked {
            let result = samples
            samples = []
            return result
        }
    }
}
