# Input architecture: hotkey & text insertion

## Global hotkey

| Mechanism | Press + release | Permission | Overhead | Verdict |
|---|---|---|---|---|
| **Carbon `RegisterEventHotKey`** + `kEventHotKeyPressed` / `kEventHotKeyReleased` | Yes | None | The system delivers only this combo's events; zero cost otherwise | **Chosen** |
| CGEventTap (keyDown/keyUp/flagsChanged) | Yes | Accessibility or Input Monitoring | Sees every keystroke system-wide | Fallback only (e.g. modifier-only hotkeys like Fn) |
| `NSEvent.addGlobalMonitorForEvents` | Yes | Accessibility | Every key event. Can't consume the key | Rejected |

Carbon hotkey APIs are old but still supported, and remain the standard way macOS apps register
global shortcuts. Notes:
- ⌥Space is consumed by the registration, so it won't type a non-breaking space in the focused app.
- Key repeat while held doesn't generate repeated "pressed" events for registered hotkeys.
  Phase 2 verifies this.
- If the user releases Option before Space, the release event still fires for the hotkey.
  Phase 2 verifies this.

## Text insertion

| Mechanism | Works in | Verdict |
|---|---|---|
| **Pasteboard + synthetic ⌘V** (CGEvent) | Native, Electron (Cursor, VS Code, Slack), terminals, browsers | **Chosen** |
| AX `kAXSelectedTextAttribute` set | Native Cocoa text views; unreliable in Electron, terminals, web | Possible optional fast path later |
| `CGEventKeyboardSetUnicodeString` typing | Most apps | Slow for long text, interacts with autocomplete/IME. Rejected |

### Clipboard preservation algorithm (Phase 5)
1. Snapshot: for each `NSPasteboardItem`, copy **every type's data** (text, RTF, images, file
   URLs, custom types). Record `changeCount`.
2. `clearContents()`, write the transcript as `.string` plus the marker types
   `org.nspasteboard.TransientType` and `org.nspasteboard.ConcealedType`, so clipboard managers
   ignore it.
3. Post ⌘V via `CGEvent` (keyDown/keyUp with `.maskCommand`) to `.cghidEventTap`.
   **Needs Accessibility permission.**
4. After a short delay (target apps read the pasteboard asynchronously; value tuned in Phase 5,
   ~50–150 ms), restore the snapshot **only if** `changeCount` still equals ours. That way a copy
   the user made meanwhile isn't overwritten.
5. Very large pasteboards (e.g. big images): the snapshot is kept in memory only for this interval.

## Active application
`NSWorkspace.shared.frontmostApplication` gives name and bundle ID, read on demand at hotkey press.
No observers or polling are needed until Phase 10.
