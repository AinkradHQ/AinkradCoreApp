import CoreUI
import SwiftUI

/// The state of a provider that no online runner can serve yet, with the one-click Install (N22): the install on a runner with
/// live progress, then AI sessions on if they were off, then the row turns Ready (the wizard follows the runners).
struct ProviderInstall: View {
    let model: AccountsModel
    let w: ConnectWizardState
    let provider: ProviderItem
    @State private var note: String?
    @State private var turningOn = false
    @Environment(\.accessibilityReduceMotion) private var reduce

    private var target: AccountRunner? { model.installTarget(provider, w.runners) }
    private var progress: ToolProgress? { target.flatMap { model.installs["\($0.id)|\(provider.harness)"] } }

    var body: some View {
        VStack(alignment: .trailing, spacing: Space.s1) {
            if let progress, progress.state == .running, let target {
                CoreMeter(
                    Double(progress.percent) / 100, height: ConnectWizardWords.barHeight,
                    label: "Installing \(ProviderWords.title(provider))"
                )
                .frame(width: ConnectWizardWords.barWidth)
                meta(ConnectWizardWords.installing(on: target.name, percent: progress.percent))
            } else if turningOn || progress?.state == .done {
                CoreMeter(1, height: ConnectWizardWords.barHeight, label: "Installed").frame(
                    width: ConnectWizardWords.barWidth)
                meta(turningOn ? "Turning on AI sessions…" : "Installed. Checking the runner…")
            } else if let target {
                Button("Install on \(target.name)") {
                    note = nil
                    Task { await model.install(provider, on: target) }
                }
                .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                .disabled(model.readOnly)
                .help("Install \(provider.harness) on \(target.name)")
                .accessibilityIdentifier("install-\(provider.id)")
                if let why = note ?? progress?.reason {
                    Text(why).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.amberInk).lineLimit(1)
                        .frame(maxWidth: ConnectWizardWords.barWidth + Space.s8 * 2, alignment: .trailing).help(why)
                }
            } else {
                StateBadge("No runner offers it", tone: .queue, symbol: "minus")
            }
        }
        .animation(reduce ? nil : Motion.out(Motion.ui), value: progress)
        .onChange(of: progress?.state) { _, state in
            guard state == .done, let r = target else { return }
            Task {
                turningOn = true
                note = await model.enableAgentsIfOff(r)
                turningOn = false
            }
        }
    }
}

extension ProviderInstall {
    fileprivate func meta(_ text: String) -> some View {
        Text(text).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary).lineLimit(1)
    }
}
