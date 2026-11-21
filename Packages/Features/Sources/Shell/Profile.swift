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
    public nonisolated static func clean(_ raw: String) -> String {
        String(
            raw.split(whereSeparator: \.isNewline).first.map { String($0) }?.trimmingCharacters(in: .whitespaces)
                .prefix(40) ?? "")
    }
    public var hasName: Bool { !name.isEmpty }
    public func set(_ raw: String) { name = Self.clean(raw) }
}

extension UserDefaults {
    /// The store for prefs. Debug runs that must not touch the real ones get the throwaway suite; once
    /// `useThrowawayForDebugRuns()` has run, `.standard` already is that suite.
    @MainActor public static func coreStore() -> UserDefaults {
        #if DEBUG
        if throwawaySuite != nil { return .standard }
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

    #if DEBUG
    /// Whether this run must leave the person's own prefs alone: a demo, a snapshot walk or audit, in-memory keys.
    public static func isThrowawayRun(_ env: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        env["CORE_DEMO"] == "1" || env["CORE_SHOTS"] == "1" || env["CORE_KEYSTORE"] == "memory"
            || env.keys.contains { $0.hasPrefix("CORE_") && ($0.hasSuffix("SNAPSHOT") || $0.hasSuffix("AUDIT")) }
    }

    /// Debug runs only (demo, snapshot walks): points `UserDefaults.standard` itself at a throwaway suite, emptied at start,
    /// so no caller can write the real `com.ainkrad.core` prefs (a Terminals walk overwrote `terminal.lastRunner` and
    /// `terminal.size`). Covers every `.standard` read and write and `@AppStorage`, without each caller knowing. Call once,
    /// before anything reads a pref.
    public static func useThrowawayForDebugRuns() {
        guard isThrowawayRun(), throwawaySuite == nil else { return }
        let name = "com.ainkrad.core.throwaway"
        guard let suite = UserDefaults(suiteName: name) else { return }
        suite.removePersistentDomain(forName: name)
        throwawaySuite = suite
        guard let real = class_getClassMethod(UserDefaults.self, #selector(getter: UserDefaults.standard)),
            let mine = class_getClassMethod(UserDefaults.self, #selector(getter: UserDefaults.coreThrowaway))
        else { return }
        method_exchangeImplementations(real, mine)
    }

    @objc fileprivate class var coreThrowaway: UserDefaults { throwawaySuite ?? UserDefaults(suiteName: nil)! }
    #endif
}

#if DEBUG
/// Set once at launch, before any other code runs, and never again: read-only after that.
nonisolated(unsafe) private var throwawaySuite: UserDefaults?
#endif
