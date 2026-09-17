import AppKit
import Observation
import VoiceFlowCore

/// Observable app state shared by the main window and the floating pill. The menu bar keeps its own copy of settings
/// and both write through the same `SettingsStore`; AppDelegate keeps them in sync.
@MainActor
@Observable
final class AppState {
    private(set) var settings: Settings
    var pipelineState: PipelineState = .idle
    var audioFlowing = false
    /// Recent input levels (0…1), newest last, for the pill's bars. Only updated while recording.
    var levels: [Double] = Array(repeating: 0, count: AppState.levelCount)
    var handsFree = false
    var triggerInstructions = "hold ⌥ to dictate"
    var triggerWarning: String?
    var modelStatus: STTModelStatus = .installed
    /// The model that needs installing, if any (German/Hindi need the multilingual model).
    var modelNeedingInstall: STTModel?
    /// Language of the current or last dictation (pill badge); nil until known.
    var dictationLanguage: OutputLanguage?
    /// Brief notice on the pill (e.g. after switching language with the shortcut).
    var notice: String?
    /// In memory only (never saved).
    var lastTranscript: String?

    static let levelCount = 14

    @ObservationIgnored let store: SettingsStore
    /// Settings saved from the window or the pill (not from the menu, which notifies AppDelegate itself).
    @ObservationIgnored var onSettingsChanged: ((Settings) -> Void)?
    @ObservationIgnored var onCancelDictation: (() -> Void)?
    @ObservationIgnored var onFinishDictation: (() -> Void)?
    @ObservationIgnored var onPermissionsMayHaveChanged: (() -> Void)?

    init(settings: Settings, store: SettingsStore) {
        self.settings = settings
        self.store = store
    }

    /// Applies an edit, saves settings.json and notifies the pipeline.
    func update(_ mutate: (inout Settings) -> Void) {
        var next = settings
        mutate(&next)
        guard next != settings else { return }
        settings = next
        do {
            try store.save(next)
        } catch {
            Log.settings.error("failed to save settings: \(error.localizedDescription, privacy: .public)")
        }
        onSettingsChanged?(next)
    }

    /// Settings changed elsewhere (menu, file edits) and already saved.
    func adopt(_ settings: Settings) {
        if settings != self.settings { self.settings = settings }
    }

    func pushLevel(_ level: Double) {
        levels.removeFirst()
        levels.append(level)
    }

    func resetLevels() {
        if levels.contains(where: { $0 != 0 }) { levels = Array(repeating: 0, count: Self.levelCount) }
    }

    // MARK: Dictionary (dictionary.json)

    var dictionaryURL: URL { UserDictionary.fileURL(in: store.fileURL.deletingLastPathComponent()) }

    func loadDictionary() -> UserDictionary { UserDictionary.load(from: dictionaryURL) }

    func saveDictionary(_ dictionary: UserDictionary) {
        do {
            try FileManager.default.createDirectory(at: dictionaryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(dictionary).write(to: dictionaryURL, options: .atomic)
        } catch {
            Log.settings.error("failed to save dictionary: \(error.localizedDescription, privacy: .public)")
        }
    }
}
