import AppKit
import Darwin

// Writes to the speech helper's pipe must fail with an error (not kill the app) if the helper has exited.
signal(SIGPIPE, SIG_IGN)

// Menu-bar-only app (LSUIElement): no Dock icon, no main window.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
