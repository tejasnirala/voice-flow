import AppKit
import CoreGraphics

/// Observes the ⌥ (Option) key on its own, system-wide, using listen-only event taps (Input Monitoring permission).
///
/// Two taps, both listen-only (they can't delay or change the user's input):
/// - **flags**: modifier-key changes only, always enabled. Detects ⌥ down/up and other modifiers joining (chords).
/// - **keys**: key-down events, **enabled only while ⌥ is held**, solely to detect chords like ⌥← or ⌥+letter.
///   Which key was pressed is never read, stored or logged.
@MainActor
final class ModifierKeyMonitor {
    enum Event { case down, up, chord }

    /// Called on the main thread with the delay from the system event timestamp to this callback.
    var onEvent: ((Event, _ latencyMs: Double) -> Void)?

    private var flagsTap: CFMachPort?
    private var keysTap: CFMachPort?
    private var sources: [CFRunLoopSource] = []
    private var optionDown = false

    /// Whether macOS allows VoiceFlow to observe keyboard events (Input Monitoring).
    static var hasPermission: Bool { CGPreflightListenEventAccess() }

    /// Shows the system Input Monitoring prompt (first time only).
    static func requestPermission() { _ = CGRequestListenEventAccess() }

    /// Returns false if the taps couldn't be created (permission missing).
    func start() -> Bool {
        guard flagsTap == nil else { return true }
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: CGEventTapCallBack = { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<ModifierKeyMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.handle(type: type, event: event) }
            return Unmanaged.passUnretained(event)
        }
        guard let flags = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                            eventsOfInterest: CGEventMask(1 << CGEventType.flagsChanged.rawValue),
                                            callback: callback, userInfo: context),
              let keys = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                           eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
                                           callback: callback, userInfo: context) else {
            return false
        }
        CGEvent.tapEnable(tap: keys, enable: false)
        for tap in [flags, keys] {
            if let source = CFMachPortCreateRunLoopSource(nil, tap, 0) {
                // Common modes: events keep arriving while VoiceFlow's own menu is open.
                CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
                sources.append(source)
            }
        }
        flagsTap = flags
        keysTap = keys
        return true
    }

    func stop() {
        for source in sources { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        sources.removeAll()
        for tap in [flagsTap, keysTap].compactMap({ $0 }) { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        flagsTap = nil
        keysTap = nil
        optionDown = false
    }

    private func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // The system can disable taps; turn the flags tap back on (the keys tap follows ⌥ state).
            if let flagsTap { CGEvent.tapEnable(tap: flagsTap, enable: true) }
            return
        case .flagsChanged:
            let flags = event.flags
            let option = flags.contains(.maskAlternate)
            let others = !flags.intersection([.maskCommand, .maskControl, .maskShift, .maskSecondaryFn]).isEmpty
            let latency = Self.latencyMs(of: event)
            if !optionDown, option {
                guard !others else { return } // e.g. ⌘⌥ pressed together: not a dictation press
                optionDown = true
                setKeysTap(enabled: true)
                onEvent?(.down, latency)
            } else if optionDown, !option {
                optionDown = false
                setKeysTap(enabled: false)
                onEvent?(.up, latency)
            } else if optionDown, others {
                onEvent?(.chord, latency)
            }
        case .keyDown:
            if optionDown { onEvent?(.chord, Self.latencyMs(of: event)) }
        default:
            break
        }
    }

    private func setKeysTap(enabled: Bool) {
        if let keysTap { CGEvent.tapEnable(tap: keysTap, enable: enabled) }
    }

    /// Delay from the event's system timestamp to now. Hardware event timestamps are nanoseconds of uptime
    /// (not `mach_absolute_time` ticks, which differ on Apple Silicon: timebase 125/3). Returns 0 if unknown.
    private static func latencyMs(of event: CGEvent) -> Double {
        let now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        guard event.timestamp > 0, now >= event.timestamp else { return 0 }
        let ms = Double(now - event.timestamp) / 1_000_000
        return ms < 60_000 ? ms : 0
    }
}
