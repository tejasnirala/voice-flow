import AppKit
import OSLog
import VoiceFlowCore

/// A plain-text report for troubleshooting, copied to the clipboard only when the owner asks (menu → Copy Diagnostics).
/// Contains versions, settings, model and permission status and VoiceFlow's recent log lines. Logs never contain
/// transcripts or audio, so neither does this.
@MainActor
enum Diagnostics {
    static func report(settings: Settings, modelStatus: String, state: String) -> String {
        let model = settings.sttModel
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        var lines = [
            "\(BuildInfo.name) \(BuildInfo.version) (build \(BuildInfo.build))",
            "macOS \(os), \(ProcessInfo.processInfo.physicalMemory / 1_073_741_824) GB RAM",
            "State: \(state)",
            "Speech model: \(model.id) — \(modelStatus); Neural Engine encoder: \(STTModelManager.hasCoreMLEncoder(for: model) ? "installed" : "missing")",
            "On-device rewrite model: \(OnDeviceRewriter.unavailableReason ?? "available")",
            "Permissions: microphone \(PermissionManager.microphone), accessibility \(PermissionManager.isAccessibilityTrusted ? "allowed" : "not allowed"), input monitoring \(ModifierKeyMonitor.hasPermission ? "allowed" : "not allowed")",
            "Settings: trigger \(settings.dictationTrigger.rawValue), mode \(settings.textMode.rawValue), mode by app \(settings.modeByApp), per-app rules \(settings.appModes.count), smart rewrite \(settings.processingMode.rawValue), paste into \(settings.pasteInto.rawValue), max \(Int(settings.maxRecordingSeconds)) s, unload after \(Int(settings.sttUnloadAfterSeconds)) s",
            "Open at login: \(LoginItem.isEnabled)",
            "App memory: \(Int(ResourceUsage.footprintMB)) MB",
            "",
            "Recent log (this launch):",
        ]
        lines += recentLog(limit: 60)
        return lines.joined(separator: "\n")
    }

    static func recentLog(limit: Int) -> [String] {
        guard let store = try? OSLogStore(scope: .currentProcessIdentifier) else { return ["(log unavailable)"] }
        let since = store.position(timeIntervalSinceLatestBoot: 0)
        let entries = (try? store.getEntries(at: since, matching: NSPredicate(format: "subsystem == %@", Log.subsystem))) ?? AnySequence([])
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let lines = entries.compactMap { $0 as? OSLogEntryLog }.map { "\(formatter.string(from: $0.date)) [\($0.category)] \($0.composedMessage)" }
        return lines.isEmpty ? ["(no entries)"] : Array(lines.suffix(limit))
    }
}
