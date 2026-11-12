import CoreUI
import SwiftUI

/// The last screen of setup (N16, D1): two machines are ready, and This Mac can be turned off before its first use.
/// The switch only records the choice; the runner is added once the Core connects and this Mac is unlocked with Touch ID.
struct MacRunnerReadyView: View {
    let macRunner: MacRunnerModel
    let finish: () -> Void
    @State private var on: Bool
    @Environment(\.corePalette) private var palette

    init(macRunner: MacRunnerModel, finish: @escaping () -> Void) {
        self.macRunner = macRunner
        self.finish = finish
        _on = State(initialValue: macRunner.useThisMac)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text("Ready: 2 machines").coreFont(size: MacTextSize.large, weight: .semibold).accessibilityAddTraits(
                .isHeader)
            Text("This Core (built-in) and This Mac").foregroundStyle(palette.text2)
            machine("server.rack", "This Core (built-in)", "Terminals and agents, always on.", enabled: true)
            machine(
                "laptopcomputer", "This Mac",
                on
                    ? "Terminals and AI sessions with your accounts, once it connects."
                    : "Off. You can turn it on in Settings, Mac.",
                enabled: on)
            Toggle("Use this Mac as a runner", isOn: $on).toggleStyle(.switch)
                .onChange(of: on) { _, v in macRunner.setPreference(v) }
                .accessibilityIdentifier("ready-mac-runner-switch")
            if on {
                Text("Ainkrad asks for Touch ID once to add this Mac. \(MacRunnerModel.terminalsWarning)")
                    .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2).fixedSize(
                        horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Continue", action: finish).coreGlassButton(prominent: true).coreShortcut(.primary)
            }
        }
    }

    private func machine(_ symbol: String, _ name: String, _ line: String, enabled: Bool) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: symbol).coreFont(size: MacTextSize.large)
                .foregroundStyle(enabled ? palette.primary : palette.text2).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(name).coreFont(size: MacTextSize.headline, weight: .semibold)
                Text(line).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.glassCard, in: coreShape(Radius.row))
        .accessibilityElement(children: .combine)
    }
}
