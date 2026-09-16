import AppKit

// Phase 0 shell: proves the SwiftPM → .app pipeline builds and launches as a
// menu-bar-only (LSUIElement) process. The real shell arrives in Phase 1.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
