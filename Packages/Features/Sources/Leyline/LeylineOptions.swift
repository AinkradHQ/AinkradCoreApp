import CoreUI
import Foundation
import SwiftUI

/// Settings, Apps, Leyline, Options (E2-4). The Core keeps no "last used" or "owner" for a host, so the two filters use what
/// this Mac knows: the hosts opened lately, and the hosts added from this Mac. Both lists are kept here, per Mac.
@MainActor enum LeylineOptions {
    static var options: AppOptions { .shared("leyline") }
    static let show = "show"
    static let calm = "calm"
    private static let usedKey = "leyline.lastOpened"
    private static let mineKey = "leyline.addedHere"
    /// "Only active" means opened in the last 30 days.
    static let activeDays = 30.0

    enum Show: String, CaseIterable {
        case everything, active, mine
        var title: String {
            switch self {
            case .everything: "Everything"
            case .active: "Only active"
            case .mine: "Only mine"
            }
        }
    }

    static var current: Show { Show(rawValue: options.string(show, "everything")) ?? .everything }
    static var calmOn: Bool { options.bool(calm, true) }

    /// The hosts the gallery shows for a choice. `opened` maps a host id to when it was last opened here, `mine` holds the ids
    /// added from this Mac.
    static func filter(_ hosts: [HostItem], show: Show, opened: [String: Date], mine: Set<String>, now: Date = Date())
        -> [HostItem]
    {
        switch show {
        case .everything: return hosts
        case .active:
            return hosts.filter { h in opened[h.id].map { now.timeIntervalSince($0) <= activeDays * 86_400 } ?? false }
        case .mine: return hosts.filter { mine.contains($0.id) }
        }
    }

    static func opened(_ d: UserDefaults = .standard) -> [String: Date] {
        (d.dictionary(forKey: usedKey) as? [String: Double] ?? [:]).mapValues { Date(timeIntervalSince1970: $0) }
    }

    static func markOpened(_ id: String, at now: Date = Date(), _ d: UserDefaults = .standard) {
        var m = d.dictionary(forKey: usedKey) as? [String: Double] ?? [:]
        m[id] = now.timeIntervalSince1970
        d.set(m, forKey: usedKey)
        options.set("opened", "\(m.count)")  // redraws the gallery
    }

    static func mine(_ d: UserDefaults = .standard) -> Set<String> { Set(d.stringArray(forKey: mineKey) ?? []) }

    static func markMine(_ id: String, _ d: UserDefaults = .standard) {
        var s = mine(d)
        s.insert(id)
        d.set(Array(s), forKey: mineKey)
    }
}

struct LeylineOptionsTab: View {
    @Environment(\.coreAccent) private var paneAccent
    let options = LeylineOptions.options

    var body: some View {
        GlassSection(
            "Hosts", sub: "What the gallery shows and how it moves", symbol: "server.rack",
            hue: GlassInk.accent(paneAccent)
        ) {
            VStack(spacing: Space.s2) {
                OptionSelectRow(
                    "Show on the map", sub: "Active means opened in the last 30 days; mine means added on this Mac",
                    symbol: "map",
                    selection: options.text(LeylineOptions.show, "everything"),
                    options: LeylineOptions.Show.allCases.map { CoreSelectOption($0.rawValue, $0.title) })
                OptionSwitchRow(
                    "Calm animations", sub: "Cards rise in and lift under the pointer", symbol: "wind",
                    isOn: options.flag(LeylineOptions.calm, true))
            }
        }
        .foregroundStyle(GlassInk.primary)
    }
}
