import Carbon.HIToolbox
import Foundation

/// System-wide hotkeys via Carbon `RegisterEventHotKey`.
///
/// Why Carbon: it delivers both press and release for exactly the registered combination, consumes the
/// keystroke (no stray character in the focused app), needs no Accessibility/Input Monitoring permission,
/// and costs nothing while the keys aren't pressed. No polling, no event tap.
@MainActor
final class GlobalHotkeyManager {
    enum Action: UInt32 {
        case dictation = 1
        /// Esc while recording. Carbon matches modifiers exactly and ⌥ is usually still held, so both
        /// Esc and ⌥Esc are registered, and only while recording.
        case cancel = 2
        case cancelWithOption = 3
        /// Cycles the dictation language (Phase 14; default ⌃⇧L).
        case cycleLanguage = 4
    }

    enum Phase { case pressed, released }

    struct RegistrationError: Error {
        let status: OSStatus
        var isAlreadyTaken: Bool { status == OSStatus(eventHotKeyExistsErr) }
    }

    /// Called on the main thread. `latencyMs` = delay from the system's event timestamp to this handler.
    var onHotkey: ((Action, Phase, _ latencyMs: Double) -> Void)?

    private static let signature: OSType = 0x5646_6C77 // 'VFlw'
    private var handler: EventHandlerRef?
    private var registered: [Action: EventHotKeyRef] = [:]

    func register(_ action: Action, keyCode: UInt32, carbonModifiers: UInt32) throws(RegistrationError) {
        try installHandlerIfNeeded()
        unregister(action)
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.signature, id: action.rawValue)
        let status = RegisterEventHotKey(keyCode, carbonModifiers, id, GetEventDispatcherTarget(), 0, &ref)
        guard status == noErr, let ref else { throw RegistrationError(status: status) }
        registered[action] = ref
    }

    func unregister(_ action: Action) {
        guard let ref = registered.removeValue(forKey: action) else { return }
        UnregisterEventHotKey(ref)
    }

    private func installHandlerIfNeeded() throws(RegistrationError) {
        guard handler == nil else { return }
        var types = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let context = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetEventDispatcherTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            let latencyMs = (GetCurrentEventTime() - GetEventTime(event)) * 1000
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr, hotKeyID.signature == GlobalHotkeyManager.signature,
                  let action = Action(rawValue: hotKeyID.id) else { return OSStatus(eventNotHandledErr) }
            let phase: Phase = GetEventKind(event) == UInt32(kEventHotKeyPressed) ? .pressed : .released
            // Carbon dispatches application events on the main thread.
            MainActor.assumeIsolated {
                Unmanaged<GlobalHotkeyManager>.fromOpaque(context).takeUnretainedValue().onHotkey?(action, phase, latencyMs)
            }
            return noErr
        }, types.count, &types, context, &handler)
        guard status == noErr else { throw RegistrationError(status: status) }
    }
}
