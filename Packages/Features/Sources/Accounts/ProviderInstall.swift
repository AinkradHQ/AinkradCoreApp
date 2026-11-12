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

    private var target: AccountRunner? { model.installTarget(provider, w.runners) }
    private var progress: ToolProgress? { target.flatMap { model.installs["\($0.id)|\(provider.harness)"] } }
    private var canInstall: Bool { AccountsModel.installable.contains(provider.harness) }
    private var many: Bool { w.runners.filter(\.online).count > 1 }

    var body: some View {
        VStack(alignment: .trailing, spacing: Space.s1) {
            if let progress, progress.state == .running {
                StateBadge("Installing… \(progress.percent)%", tone: .run, symbol: "arrow.down.circle")
                CoreMeter(Double(progress.percent) / 100, label: "Installing \(ProviderWords.title(provider))")
                    .frame(width: 150)
                Text(progress.step.isEmpty ? "Working…" : progress.step).coreFont(size: MacTextSize.meta)
                    .foregroundStyle(GlassInk.secondary).lineLimit(1)
            } else if turningOn || progress?.state == .done {
                StateBadge("Almost ready", tone: .run, symbol: "checkmark.circle")
                Text(turningOn ? "Turning on AI sessions…" : "Installed. Checking the runner…")
                    .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
            } else {
                StateBadge("Not installed", tone: .queue, symbol: "arrow.down.circle")
                if canInstall, let target {
                    AccLink(title: many ? "Install on \(target.name)" : "Install", symbol: "arrow.down.to.line") {
                        note = nil
                        Task { await model.install(provider, on: target) }
                    }
                    .disabled(model.readOnly)
                    .accessibilityIdentifier("install-\(provider.id)")
                } else if !canInstall {
                    Text("Install \(provider.harness) on a runner.").coreFont(size: MacTextSize.meta)
                        .foregroundStyle(GlassInk.secondary)
                }
                if let why = note ?? progress?.reason {
                    Text(why).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.amberInk)
                        .multilineTextAlignment(.trailing).frame(maxWidth: 220, alignment: .trailing)
                }
            }
        }
        .animation(.smooth(duration: 0.25), value: progress)
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
