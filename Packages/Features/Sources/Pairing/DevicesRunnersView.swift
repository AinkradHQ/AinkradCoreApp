import CoreUI
import Shell
import SwiftUI

/// The tabs of the Devices & Runners app (D-11): the one place for what reaches this Core and what works for it.
enum HubTab: String, CaseIterable, Identifiable, Sendable {
    case devices = "Devices"
    case runners = "Runners"
    case thisMac = "This Mac"
    case about = "About"
    var id: String { rawValue }

    /// The tab a launcher entry lands on; nil for an entry that is not part of this app.
    static func forEntry(_ id: String) -> HubTab? {
        switch id {
        case "devices", "add-device", "add-device-advanced", "devices-runners": .devices
        case "runners": .runners
        case "mac-runner": .thisMac
        default: nil
        }
    }
}

extension AppModel {
    /// Opens Devices & Runners on `tab`.
    func openHub(_ tab: HubTab) {
        hubTab = tab
        var spec = PaneSpec(
            id: "devices-runners", title: "Devices & Runners", sub: "Home Core", symbol: "iphone.and.arrow.forward",
            minWidth: 720
        ) { DevicesRunnersView(app: self) }
        spec.tab = "Devices & Runners"
        shell.openPane(spec)
    }
}

/// Devices | Runners | This Mac | About, each reusing the screen it had in Settings or its own pane.
struct DevicesRunnersView: View {
    @Bindable var app: AppModel

    private var tabs: [HubTab] { HubTab.allCases.filter { $0 != .thisMac || app.isAdminDevice } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CoreTabs("Devices and runners", tabs: tabs.map { CoreTab($0, $0.rawValue) }, selection: $app.hubTab)
            .fixedSize().padding(.horizontal, Space.s4).padding(.top, Space.s4)
            switch app.hubTab {
            case .devices: page { DevicesSection(app: app) }
            case .runners:
                if let terminals = app.terminals {
                    terminals.runnersView()
                } else {
                    page { NotConnectedNote(what: "Runners") }
                }
            case .thisMac:
                page {
                    Header("This Mac", "Let Core use this Mac to run work while you are away.")
                    MacRunnerSection(
                        model: app.macRunner,
                        accounts: app.macRunner.deviceID.flatMap { app.terminals?.accountsAnswer(forRunner: $0) },
                        connected: app.macRunner.deviceID.flatMap { app.terminals?.isOnline(runner: $0) })
                }
            case .about:
                page {
                    Header("Ainkrad Core", "Which Core this is and what this device may do on it.")
                    AboutBlock(app: app)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func page<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) { content() }
                .frame(maxWidth: .infinity, alignment: .leading).padding(Space.s4)
        }
    }

    private struct Header: View {
        let title: String
        let sub: String
        @Environment(\.corePalette) private var palette
        init(_ title: String, _ sub: String) {
            self.title = title
            self.sub = sub
        }
        var body: some View {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text(title).coreFont(size: MacTextSize.title, weight: .semibold).accessibilityAddTraits(.isHeader)
                Text(sub).foregroundStyle(palette.text2)
            }
        }
    }
}
