import CryptoKit
import Foundation
import VoiceFlowCore

/// Locates and validates STT model files in `~/Library/Application Support/VoiceFlow/models/`.
/// Never downloads anything: a missing model is reported with the setup command that installs it.
enum STTModelManager {
    static var modelsDirectory: URL {
        SettingsStore.applicationSupportDirectory().appendingPathComponent("models", isDirectory: true)
    }

    static func url(for model: STTModel) -> URL {
        modelsDirectory.appendingPathComponent(model.runtimeDirectory, isDirectory: true).appendingPathComponent(model.fileName)
    }

    private static var recordsURL: URL { modelsDirectory.appendingPathComponent("verified.json") }

    /// Cheap check (file attributes only). Safe to call on the main thread.
    static func quickStatus(for model: STTModel) -> STTModelStatus {
        STTModelValidation.quickStatus(for: model, fileSize: attributes(of: model)?.size)
    }

    /// Full check. Hashes the file (~1 s for 0.8 GB) only if it hasn't been verified in its current state.
    /// Call off the main thread.
    static func verify(_ model: STTModel) -> (status: STTModelStatus, hashedSeconds: Double) {
        guard let attrs = attributes(of: model) else { return (.missing, 0) }
        let quick = STTModelValidation.quickStatus(for: model, fileSize: attrs.size)
        guard quick == .installed else { return (quick, 0) }

        var records = loadRecords()
        if records.contains(where: { $0.matches(model, sizeBytes: attrs.size, modificationTime: attrs.modified) }) {
            return (.installed, 0)
        }
        let start = DispatchTime.now().uptimeNanoseconds
        guard let digest = sha256(of: url(for: model)) else { return (.corrupted(reason: "unreadable"), 0) }
        let seconds = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9
        let status = STTModelValidation.status(for: model, computedSHA256: digest)
        if status == .installed {
            records.removeAll { $0.modelID == model.id }
            records.append(ModelVerificationRecord(modelID: model.id, sizeBytes: attrs.size,
                                                   modificationTime: attrs.modified, sha256: digest))
            saveRecords(records)
        }
        return (status, seconds)
    }

    private static func attributes(of model: STTModel) -> (size: Int64, modified: Double)? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url(for: model).path),
              let size = attrs[.size] as? NSNumber else { return nil }
        let modified = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return (size.int64Value, modified)
    }

    private static func sha256(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        // Drain each 4 MB chunk immediately. Without a pool, Foundation's autoreleased buffers accumulate on a
        // background thread until the whole file (~0.8 GB) is held in memory.
        while true {
            let more = autoreleasepool { () -> Bool in
                guard let chunk = try? handle.read(upToCount: 4 << 20), !chunk.isEmpty else { return false }
                hasher.update(data: chunk)
                return true
            }
            if !more { break }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func loadRecords() -> [ModelVerificationRecord] {
        guard let data = try? Data(contentsOf: recordsURL) else { return [] }
        return (try? JSONDecoder().decode([ModelVerificationRecord].self, from: data)) ?? []
    }

    private static func saveRecords(_ records: [ModelVerificationRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: recordsURL, options: .atomic)
    }

    /// The developer vocabulary bundled with the app (Resources/developer-vocabulary.txt), used as Whisper's
    /// initial prompt. Falls back to the source tree when running unbundled (`swift run`).
    static func vocabularyPrompt() -> String? {
        let bundled = Bundle.main.url(forResource: "developer-vocabulary", withExtension: "txt")
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/developer-vocabulary.txt")
        guard let url = bundled ?? (FileManager.default.fileExists(atPath: source.path) ? source : nil),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
