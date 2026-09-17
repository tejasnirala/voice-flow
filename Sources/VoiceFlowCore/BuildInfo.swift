import Foundation

/// Static build metadata. Kept in Core so tests and the app agree on it.
public enum BuildInfo {
    public static let name = "VoiceFlow"
    /// Marketing version; the bundle's Info.plist wins when running as an app.
    public static let defaultVersion = "1.0.0"

    public static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? defaultVersion
    }

    /// Build number (git commit count at build time, set by scripts/build-app.sh), or "dev".
    public static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "dev"
    }
}
