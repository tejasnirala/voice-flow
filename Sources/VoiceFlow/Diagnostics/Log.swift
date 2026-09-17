import os

/// Unified-logging categories. Privacy rule: log states, durations and sizes only, never transcript text
/// or audio. View with: `log stream --predicate 'subsystem == "local.voiceflow.VoiceFlow"'`
enum Log {
    static let subsystem = "local.voiceflow.VoiceFlow"
    static let lifecycle = Logger(subsystem: subsystem, category: "lifecycle")
    static let settings = Logger(subsystem: subsystem, category: "settings")
}
