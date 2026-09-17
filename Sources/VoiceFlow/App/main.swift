import AppKit

import Darwin
import VoiceFlowCore

// ggml's Metal backend, when residency sets are enabled, starts a thread that wakes every 5 ms for the whole
// life of the process (~200 wakeups/s, even after the model is unloaded). Disable residency sets before whisper
// initializes. Measured trade-off: docs/PERFORMANCE.md §3.4. Set VOICEFLOW_METAL_RESIDENCY=1 to re-enable for A/B tests.
if ProcessInfo.processInfo.environment["VOICEFLOW_METAL_RESIDENCY"] != "1" {
    setenv("GGML_METAL_NO_RESIDENCY", "1", 1)
}

// Developer benchmark mode runs headless and exits; see BenchmarkMode.swift.
let launchSettings = SettingsStore(directory: SettingsStore.applicationSupportDirectory()).load().settings
if MainActor.assumeIsolated({ BenchmarkMode.runIfRequested(settings: launchSettings) }) {
    dispatchMain()
}

// Menu-bar-only app (LSUIElement): no Dock icon, no main window.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
