import Foundation
import Testing

/// Per-app accent (E2-7): views read the accent from `@Environment(\.coreAccent)`, never `GlassInk.blue` (the global one).
struct AccentSourceScanTests {
    /// Files that may still say `GlassInk.blue`: static lookup tables and helpers with no view or environment to read
    /// from. They resolve to the global accent, which is the app default. Thread the colour in before adding to this list.
    static let allowed: Set<String> = [
        "Pairing/Controls.swift", "Pairing/AddWizardSteps.swift", "Shell/SettingsView.swift", "Admin/OpsView.swift",
        "Admin/AuditView.swift", "Admin/SettingWords.swift", "Agents/SessionTile.swift", "Accounts/Costs.swift",
        "Accounts/Connections/ConnModels.swift", "Accounts/AccountsLook.swift", "Brain/RoomsTab.swift",
        "LoreEditor/LoreBlocks.swift",
        // Views merged from the other 0.10 epics after E2-7: they move to the pane accent in a follow-up.
        "Accounts/AIOrder/AddAccountDialog.swift",
        "Accounts/AIOrder/AdvancedTabs.swift",
        "Accounts/AIOrder/AIOrderRow.swift",
        "Accounts/AIOrder/AIOrderView.swift",
        "Accounts/AIOrder/GuidedSignInViews.swift",
        "Accounts/Connections/ConnAddView.swift",
        "Accounts/Connections/ConnParts.swift",
        "Agents/MarkdownText.swift",
        "Agents/SessionPanelTabs.swift",
        "Brain/BrainPane.swift",
        "Brain/Calm/RadialMap.swift",
        "Leyline/HostCard.swift",
        "Leyline/HostSpaceCards.swift",
        "Lore/LoreBars.swift",
        "Lore/QuickCaptureView.swift",
        "Pairing/AddRunnerView.swift",
        "Pairing/Registration.swift",
        "Pairing/Setup/SetupTourParts.swift",
        "Pairing/Setup/SetupTourView.swift",
        "Pairing/SetupWizardView.swift",
        "Shell/Clocks.swift",
        "Shell/LauncherView.swift",
        "Shell/UnlockCard.swift",
        "Shell/WidgetBodiesBrain.swift",
        "Shell/WidgetBodiesKinds.swift",
        "Shell/WidgetBodiesNew.swift",
        "Shell/WidgetCalendar.swift",
        "Shell/WidgetGallery.swift",
        "Shell/WidgetWeather.swift",
        "Terminals/NewTerminalView.swift",
        "Terminals/RunnersRows.swift",
        "Terminals/TerminalCard.swift",
        "Terminals/TerminalsListView.swift",
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
