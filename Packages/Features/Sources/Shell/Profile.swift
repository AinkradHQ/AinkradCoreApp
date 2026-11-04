import Foundation
import Observation

/// What this Mac knows about the person: the name the greeting uses. Local to this Mac (not a Core field); not a secret.
@MainActor @Observable
public final class UserProfile {
    private let defaults: UserDefaults
    static let nameKey = "ainkrad.core.profile.name"
    public var name: String {
        didSet { defaults.set(name, forKey: Self.nameKey) }
    }
    public init(defaults: UserDefaults) {
        self.defaults = defaults
        name = Self.clean(defaults.string(forKey: Self.nameKey) ?? "")
    }
    /// Trimmed, one line, 40 characters at most.
    public static func clean(_ raw: String) -> String {
        String(raw.split(whereSeparator: \.isNewline).first.map { String($0) }?.trimmingCharacters(in: .whitespaces).prefix(40) ?? "")
    }
    public var hasName: Bool { !name.isEmpty }
    public func set(_ raw: String) { name = Self.clean(raw) }
}

extension UserDefaults {
    /// The store for prefs. Debug runs that must not touch the real ones (demo, in-memory keys) get a throwaway suite.
    @MainActor public static func coreStore() -> UserDefaults {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        if env["CORE_DEMO"] == "1" || env["CORE_KEYSTORE"] == "memory" {
            let suite = "com.ainkrad.core.throwaway"
            let d = UserDefaults(suiteName: suite) ?? .standard
            d.removePersistentDomain(forName: suite)
            return d
        }
        #endif
        return .standard
    }
}
