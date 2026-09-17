/// A known STT model file and how to validate it. Models live outside the app bundle, in
/// `~/Library/Application Support/VoiceFlow/models/<runtime>/`, and are installed by the setup script.
public struct STTModel: Equatable, Sendable {
    public var id: String
    public var runtimeDirectory: String
    public var fileName: String
    public var sizeBytes: Int64
    public var sha256: String
    /// Whisper language code passed to the decoder.
    public var language: String
    public var displayName: String

    /// Alternate: most accurate on terms, but produced an invented phrase (2.0 per 100 clips > approved 1 per 100);
    /// multilingual (docs/ACCURACY.md §5.8). Hashes and sizes from Hugging Face LFS metadata.
    public static let largeV3TurboQ8 = STTModel(
        id: "large-v3-turbo-q8_0", runtimeDirectory: "whisper", fileName: "ggml-large-v3-turbo-q8_0.bin",
        sizeBytes: 874_188_075, sha256: "317eb69c11673c9de1e1f0d459b253999804ec71ac4c23c17ecf5fbe24e259a1",
        language: "en", displayName: "Whisper large-v3-turbo (q8_0)")

    /// Default: passes the approved accuracy threshold on the owner's recordings (docs/ACCURACY.md §5.8).
    public static let mediumEnQ8 = STTModel(
        id: "medium.en-q8_0", runtimeDirectory: "whisper", fileName: "ggml-medium.en-q8_0.bin",
        sizeBytes: 823_382_461, sha256: "43fa2cd084de5a04399a896a9a7a786064e221365c01700cea4666005218f11c",
        language: "en", displayName: "Whisper medium.en (q8_0)")

    public static let catalog: [STTModel] = [mediumEnQ8, largeV3TurboQ8]

    public static func model(id: String) -> STTModel? { catalog.first { $0.id == id } }

    /// Core ML encoder directory whisper.cpp looks for next to the model: "ggml-medium.en-q8_0.bin" →
    /// "ggml-medium.en-encoder.mlmodelc" (extension and quantization suffix removed). When present, the encoder runs on
    /// the Neural Engine; otherwise on Metal.
    public var coreMLEncoderDirectoryName: String { Self.coreMLEncoderDirectoryName(forModelFileName: fileName) }

    public static func coreMLEncoderDirectoryName(forModelFileName fileName: String) -> String {
        var base = fileName.hasSuffix(".bin") ? String(fileName.dropLast(4)) : fileName
        if let dash = base.lastIndex(of: "-") {
            let suffix = base[base.index(after: dash)...]
            if suffix.count == 4, suffix.first == "q", suffix.dropFirst(2).first == "_" { base = String(base[..<dash]) }
        }
        return base + "-encoder.mlmodelc"
    }

    /// Shell command that installs this model (shown to the user when it's missing).
    public var installCommand: String {
        "scripts/fetch-models.sh whisper \(id)"
    }

    /// Command that installs the Core ML (Neural Engine) encoder for this model, if one exists.
    public var coreMLEncoderInstallCommand: String? {
        guard runtimeDirectory == "whisper", let base = coreMLEncoderDirectoryName.components(separatedBy: "-encoder").first,
              base.hasPrefix("ggml-") else { return nil }
        return "scripts/fetch-models.sh whisper-coreml \(base.dropFirst("ggml-".count))"
    }
}

/// Validation state of a model file.
public enum STTModelStatus: Equatable, Sendable {
    case installed
    case missing
    /// Size or checksum doesn't match the catalog.
    case corrupted(reason: String)
    /// The runtime refused to load it.
    case incompatible(reason: String)
}

/// Remembers that a model file already passed a full SHA-256 check, so the ~1 s hash of a large file runs once,
/// not on every load. Re-verification happens when size or modification time change.
public struct ModelVerificationRecord: Codable, Equatable, Sendable {
    public var modelID: String
    public var sizeBytes: Int64
    public var modificationTime: Double
    public var sha256: String

    public init(modelID: String, sizeBytes: Int64, modificationTime: Double, sha256: String) {
        self.modelID = modelID
        self.sizeBytes = sizeBytes
        self.modificationTime = modificationTime
        self.sha256 = sha256
    }

    public func matches(_ model: STTModel, sizeBytes: Int64, modificationTime: Double) -> Bool {
        modelID == model.id && sha256 == model.sha256 && self.sizeBytes == sizeBytes && self.modificationTime == modificationTime
    }
}

public enum STTModelValidation {
    /// Cheap check from file attributes only (used at launch and before every load).
    public static func quickStatus(for model: STTModel, fileSize: Int64?) -> STTModelStatus {
        guard let fileSize else { return .missing }
        guard fileSize == model.sizeBytes else {
            return .corrupted(reason: "size \(fileSize) bytes, expected \(model.sizeBytes)")
        }
        return .installed
    }

    /// Full check result from a computed digest.
    public static func status(for model: STTModel, computedSHA256: String) -> STTModelStatus {
        computedSHA256.lowercased() == model.sha256 ? .installed : .corrupted(reason: "checksum mismatch")
    }
}
