import AVFoundation
import VoiceFlowCore

/// Writes a recording to `debug-recordings/` when `Settings.saveRecordingsForDebugging` is on (off by default).
/// Used to verify capture quality and to collect in-app benchmark clips. Nothing is saved otherwise.
enum DebugRecordingWriter {
    static var directory: URL {
        SettingsStore.applicationSupportDirectory().appendingPathComponent("debug-recordings", isDirectory: true)
    }

    static func write(_ samples: [Float], sampleRate: Double) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        let url = directory.appendingPathComponent("\(formatter.string(from: Date())).wav")
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sampleRate,
                                       AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
                                       AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { return url }
        samples.withUnsafeBufferPointer { src in
            if let base = src.baseAddress { buffer.floatChannelData![0].update(from: base, count: samples.count) }
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        try file.write(from: buffer)
        return url
    }
}
