import ServiceManagement

/// "Open at Login" through macOS's own login items (no helper app or launch agent of ours).
@MainActor
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        Log.lifecycle.notice("open at login \(enabled ? "enabled" : "disabled", privacy: .public)")
    }
}
