import Foundation
import SwiftUI
import Testing

@testable import Shell

@MainActor
struct SettingsTabsTests {
    private func registry() -> SettingsRegistry {
        SettingsRegistry(defaults: UserDefaults(suiteName: "settings-tabs-\(UUID().uuidString)")!)
    }
    private func tab(_ id: String, order: Int = 0, advanced: Bool = false) -> SettingsTab {
        SettingsTab(id, id.capitalized, order: order, advanced: advanced) { EmptyView() }
    }
    private func page(_ id: String, _ g: SettingsGroup, order: Int = 0, advancedOnly: Bool = false) -> SettingsSection {
        SettingsSection(id: id, group: g, title: id, symbol: "gear", order: order, advancedOnly: advancedOnly) {
            EmptyView()
        }
    }

    @Test func aSectionShowsItsFirstTabUntilOneIsPicked() {
        let r = registry()
        let s = SettingsSection(
            id: "core", group: .core, title: "Core", symbol: "gear", tabs: [tab("b", order: 1), tab("a", order: 0)])
        r.section(s)
        #expect(r.currentTab(of: s)?.id == "a")
        r.selectTab("b", in: "core")
        #expect(r.currentTab(of: s)?.id == "b")
        r.selectTab("gone", in: "core")
        #expect(r.currentTab(of: s)?.id == "a")
    }

    @Test func advancedAddsTabsAndAPickedAdvancedTabFallsBack() {
        let r = registry()
        let s = SettingsSection(
            id: "core", group: .core, title: "Core", symbol: "gear",
            tabs: [tab("overview"), tab("updates", order: 1), tab("network", order: 2, advanced: true)])
        r.section(s)
        #expect(r.tabs(of: s).map(\.id) == ["overview", "updates"])
        r.advanced = true
        #expect(r.tabs(of: s).map(\.id) == ["overview", "updates", "network"])
        r.selectTab("network", in: "core")
        #expect(r.currentTab(of: s)?.id == "network")
        r.advanced = false
        #expect(r.currentTab(of: s)?.id == "overview")
    }

    @Test func otherModulesAddAndReplaceTabsAndADeviceCanHideOne() {
        let r = registry()
        r.tab("core", tab("limits", order: 9, advanced: true))  // before the section exists
        let s = SettingsSection(id: "core", group: .core, title: "Core", symbol: "gear", tabs: [tab("overview")])
        r.section(s)
        r.tab("core", tab("overview", order: 5))
        r.advanced = true
        #expect(r.tabs(of: s).map(\.id) == ["overview", "limits"])
        r.hidden = ["core.limits"]
        #expect(r.tabs(of: s).map(\.id) == ["overview"])
    }

    @Test func advancedIsKeptAcrossLaunches() {
        let d = UserDefaults(suiteName: "settings-tabs-\(UUID().uuidString)")!
        let a = SettingsRegistry(defaults: d)
        #expect(!a.advanced)
        a.advanced = true
        #expect(SettingsRegistry(defaults: d).advanced)
        #expect(d.bool(forKey: "core.settings.advanced"))
    }

    @Test func groupsRunGeneralAppsCoreAndAdvancedOnlyPagesWaitForAdvanced() {
        let r = registry()
        r.section(page("devices", .core, order: 1))
        r.section(page("lockouts", .core, order: 2, advancedOnly: true))
        r.section(page("terminal", .apps))
        r.section(page("appearance", .general, order: 1))
        r.section(page("you", .general, order: 0))
        #expect(SettingsGroup.allCases.map(\.rawValue) == ["General", "Apps", "Core"])
        #expect(r.grouped().map(\.0) == [.general, .apps, .core])
        #expect(r.grouped().flatMap { $0.1.map(\.id) } == ["you", "appearance", "terminal", "devices"])
        r.advanced = true
        #expect(r.grouped().last?.1.map(\.id) == ["devices", "lockouts"])
    }

    @Test func aSelectedPageThatIsGoneFallsBackToTheFirstInTheNav() {
        let r = registry()
        r.section(page("lockouts", .core, advancedOnly: true))
        r.section(page("you", .general))
        r.selected = "lockouts"
        #expect(r.current()?.id == "you")
        r.advanced = true
        #expect(r.current()?.id == "lockouts")
    }
}

@MainActor
struct SettingsPartTests {
    @Test func aPartShowsItsHalfAndAllShowsBoth() {
        #expect(SettingsPart.look.showsLook && !SettingsPart.look.showsOptions)
        #expect(!SettingsPart.options.showsLook && SettingsPart.options.showsOptions)
        #expect(SettingsPart.all.showsLook && SettingsPart.all.showsOptions)
    }
}
