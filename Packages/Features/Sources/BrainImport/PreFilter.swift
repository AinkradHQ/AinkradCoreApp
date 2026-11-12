import Foundation

/// What a collector never reads (Q-18 and the refusal rules): restricted file kinds and the
/// deprecated projects. A skip is counted by reason, never kept as text.
public enum PreFilter {
    public static let deprecatedProjects = ["GitScope", "Finvo", "Habtic", "ILINK", "JoseOs"]

    private static let restrictedExtensions: Set<String> = [
        "pem", "p8", "p12", "pfx", "key", "crt", "cer", "jks", "keystore", "kdbx", "ppk",
    ]
    private static let restrictedNames: Set<String> = [
        "id_rsa", "id_ed25519", "id_ecdsa", "id_dsa", ".npmrc", ".netrc", "credentials",
    ]
    private static let restrictedDirs: Set<String> = ["contracts", "contract", "agreements", "nda"]

    /// Mirrors `brain_model::rules::restricted_path`.
    public static func isRestricted(_ path: String) -> Bool {
        let parts = path.lowercased().split(whereSeparator: { $0 == "/" || $0 == "\\" }).map(String.init)
        guard let file = parts.last else { return false }
        if file == ".env" || file.hasPrefix(".env.") || restrictedNames.contains(file) { return true }
        if let dot = file.lastIndex(of: "."), restrictedExtensions.contains(String(file[file.index(after: dot)...])) {
            return true
        }
        return parts.dropLast().contains(where: restrictedDirs.contains)
    }

    /// The deprecated project a path or working directory names, if any. Claude Code names a
    /// project folder by its path with `/` turned into `-`, so a dash-separated token counts too.
    public static func deprecatedProject(in path: String) -> String? {
        let parts = path.split(whereSeparator: { $0 == "/" || $0 == "\\" || $0 == "-" }).map(String.init)
        return deprecatedProjects.first { name in parts.contains { $0.caseInsensitiveCompare(name) == .orderedSame } }
    }

    /// Why a file must not be opened, or nil.
    public static func skipReason(path: String) -> String? {
        if isRestricted(path) { return "restricted" }
        if let p = deprecatedProject(in: path) { return "deprecated:\(p)" }
        return nil
    }
}

/// Counts of what a collector found and skipped, for the wizard's "skipped by rule" lines.
public struct CollectReport: Sendable, Equatable {
    public var found = 0
    public var items = 0
    public var skipped: [String: Int] = [:]
    /// Newest modified time among the files an incremental read took; nil when it read none.
    public var newest: Date?
    public init() {}
}
