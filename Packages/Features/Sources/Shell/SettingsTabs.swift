import SwiftUI

/// One top tab of a Settings page.
public struct SettingsTab: Identifiable {
    public let id: String
    public let title: String
    public let order: Int
    /// Only while the Advanced switch is on.
    public let advanced: Bool
    public let content: AnyView
    public init<V: View>(
        _ id: String, _ title: String, order: Int = 0, advanced: Bool = false, @ViewBuilder content: () -> V
    ) {
        self.id = id
        self.title = title
        self.order = order
        self.advanced = advanced
        self.content = AnyView(content())
    }
}

extension SettingsRegistry {
    /// Adds a tab to a section another module owns (a tab with the same id is replaced). Works before the section exists.
    public func tab(_ sectionID: String, _ tab: SettingsTab) {
        var list = extraTabs[sectionID, default: []]
        list.removeAll { $0.id == tab.id }
        list.append(tab)
        extraTabs[sectionID] = list
    }

    /// The tabs to show for a section: its own and those added to it, in `order`, minus Advanced ones while Advanced is off
    /// and minus tabs hidden for this device (`hidden` holds "section.tab").
    func tabs(of s: SettingsSection) -> [SettingsTab] {
        var byID: [String: SettingsTab] = [:]
        var ids: [String] = []
        for t in s.tabs + (extraTabs[s.id] ?? []) {
            if byID[t.id] == nil { ids.append(t.id) }
            byID[t.id] = t
        }
        return ids.enumerated()
            .compactMap { i, id in byID[id].map { (i, $0) } }
            .filter { _, t in (advanced || !t.advanced) && !hidden.contains("\(s.id).\(t.id)") }
            .sorted { ($0.1.order, $0.0) < ($1.1.order, $1.0) }
            .map { $0.1 }
    }

    /// The tab shown: the one picked in this section, falling back to the first when it is gone (Advanced turned off).
    func currentTab(of s: SettingsSection) -> SettingsTab? {
        let all = tabs(of: s)
        return all.first { $0.id == tabChoice[s.id] } ?? all.first
    }

    public func selectTab(_ id: String, in sectionID: String) {
        tabChoice[sectionID] = id
    }
}
