import CoreUI
import Shell
import SwiftUI

/// Settings, Apps, Runners (E2-4): Look, and the two options the mockup shows. Both are the real switches: "Update runners
/// automatically" is the Core's automatic-update setting (the one on Core, Updates), and "Use this Mac as a runner" is the
/// This Mac switch of Devices & Runners.
struct RunnersOptionsTab: View {
    @Environment(\.coreAccent) private var paneAccent
    let app: AppModel

    var body: some View {
        GlassSection("Runners", sub: "The machines that do the work for your Core", symbol: "server.rack", hue: GlassInk.accent(paneAccent)) {
            VStack(spacing: Space.s2) {
                if app.shell.corePage.supported {
                    OptionSwitchRow(
                        "Update runners automatically", sub: "At night, one at a time. The same switch as Core, Updates",
                        symbol: "arrow.down.circle",
                        isOn: Binding(
                            get: { app.shell.corePage.prefs.autoUpdate },
                            set: { on in Task { await app.shell.corePage.save(autoUpdate: on) } }))
                } else {
                    CoreRow(
                        "Update runners automatically", subtitle: "This Core is too old to keep this setting.",
                        symbol: "arrow.down.circle", trailing: { EmptyView() })
                }
                if app.macRunner.isAvailable {
                    OptionSwitchRow(
                        "Use this Mac as a runner", sub: "Only while you are signed in", symbol: "desktopcomputer",
                        isOn: Binding(
                            get: { app.macRunner.useThisMac },
                            set: { on in Task { await app.macRunner.setUseThisMac(on) } }))
                    .disabled(app.macRunner.isBusy)
                }
            }
        }
        .foregroundStyle(GlassInk.primary)
        .task { await app.shell.corePage.load() }
    }
}
