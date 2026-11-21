import Foundation
import Testing

/// Per-app accent (E2-7): views read the accent from `@Environment(\.coreAccent)`, never `GlassInk.blue` (the global one).
struct AccentSourceScanTests {
    /// Deliberate exceptions: static lookup tables, enum helpers and a non-view closure with no environment to read from.
    /// `GlassInk.blue` is the live global accent (Settings, Appearance), so they follow it; only a pane override is skipped.
    static let allowed: Set<String> = [
        "Accounts/AccountsLook.swift", "Accounts/Connections/ConnModels.swift", "Accounts/Costs.swift",
        "Admin/AuditView.swift", "Admin/OpsView.swift", "Admin/SettingWords.swift", "Agents/SessionTile.swift",
        "Brain/RoomsTab.swift",
        "LoreEditor/LoreBlocks.swift", "Pairing/Controls.swift", "Pairing/Registration.swift",
        "Shell/SettingsView.swift",
    ]

    @Test func noViewReadsTheGlobalAccentDirectly() throws {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { url.deleteLastPathComponent() }  // Tests/ShellTests/<file> -> Packages/Features
        let sources = url.appendingPathComponent("Sources")
        let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        let pattern = try Regex(#"GlassInk\.blue\b"#)
        var offenders: [String] = []
        for case let file as URL in files where file.pathExtension == "swift" {
            let rel = String(file.path.dropFirst(sources.path.count + 1))
            guard !Self.allowed.contains(rel) else { continue }
            if try String(contentsOf: file, encoding: .utf8).contains(pattern) { offenders.append(rel) }
        }
        #expect(offenders.isEmpty, "Read the accent from @Environment(\\.coreAccent): \(offenders.sorted())")
    }
}
