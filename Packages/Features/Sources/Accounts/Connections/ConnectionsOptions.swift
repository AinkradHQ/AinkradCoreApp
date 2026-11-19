import CoreUI
import SwiftUI

/// Settings, Apps, Connections, Options (E2-4): how often this Mac asks the Core to check each sign-in, and whether a sign-in
/// that stopped working is tried again by itself. `ConnectionsModel.startChecks` reads both.
@MainActor enum ConnectionsOptions {
    static var options: AppOptions { .shared("connections") }
    static let reconnect = "reconnect"
    static let every = "every"

    static let intervals: [(id: String, title: String, seconds: Double)] = [
        ("1m", "Minute", 60), ("5m", "5 minutes", 300), ("1h", "Hour", 3600),
    ]

    static func seconds(_ id: String) -> Double { intervals.first { $0.id == id }?.seconds ?? 300 }

    /// Which sign-ins a round tests: every connected one, and the ones that need a look only when reconnecting is on.
    static func due(_ items: [ConnItem], reconnect: Bool) -> [ConnItem] {
        items.filter { $0.status == .connected || ($0.status == .needsLook && reconnect) }
    }
}

struct ConnectionsOptionsTab: View {
    let options = ConnectionsOptions.options

    var body: some View {
        GlassSection("Sign-ins", sub: "While Ainkrad is open", symbol: "link", hue: GlassInk.blue) {
            VStack(spacing: Space.s2) {
                OptionSwitchRow(
                    "Reconnect automatically", sub: "Try a sign-in that stopped working again at each check",
                    symbol: "arrow.triangle.2.circlepath", isOn: options.flag(ConnectionsOptions.reconnect, true))
                OptionSelectRow(
                    "Check connections every", symbol: "clock", selection: options.text(ConnectionsOptions.every, "5m"),
                    options: ConnectionsOptions.intervals.map { CoreSelectOption($0.id, $0.title) })
            }
        }
        .foregroundStyle(GlassInk.primary)
    }
}
