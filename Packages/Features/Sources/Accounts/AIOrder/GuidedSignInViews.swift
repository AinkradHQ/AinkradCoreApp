import CoreUI
import SwiftUI

/// No online runner can run this sign-in: say why and offer the real fix, never a button that does nothing. When the Core
/// can install the provider's app on a runner (its own one first), that is the main action, with its progress here.
struct NoRunnerView: View {
    /// What an install offers or is doing now.
    struct Install {
        let runner: String
        var progress: ToolProgress?
        /// The app is in; the runner restarts with it before it can sign in.
        var waiting = false
        var running = false
        var note: String?
        let start: () -> Void
    }

    let provider: String
    let choice: RunnerChoice
    var install: Install?
    let openRunners: () -> Void
    let back: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VStack(spacing: Space.s2) {
                ProviderTile(name: provider, size: Space.s8 * 2)
                Text(install == nil ? "No runner can sign in yet" : "Install \(provider) first")
                    .coreFont(size: MacTextSize.large, weight: .bold)
                Text(words).foregroundStyle(GlassInk.secondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            if let i = install, i.running { progress(i) }
            if let why = install?.note ?? install?.progress.flatMap({ $0.state == .failed ? $0.reason : nil }) {
                AccIssue(text: why)
            }
            if let i = install {
                HStack(spacing: Space.s2) {
                    AccLink(title: "Open Machines", symbol: "server.rack", action: openRunners)
                    Spacer(minLength: Space.s2)
                    AccDialogButtons(
                        confirm: i.progress?.state == .failed ? "Try again" : "Install on \(i.runner)",
                        cancelTitle: "Back", busy: i.running, enabled: !i.running, cancel: back, run: i.start)
                }
            } else {
                AccDialogButtons(confirm: "Open Machines", cancelTitle: "Back", cancel: back, run: openRunners)
            }
        }
        .accessibilityIdentifier("no-runner")
    }

    private var words: String {
        guard let i = install else { return choice.why(provider: provider) }
        return "No runner can sign in to \(provider) yet. Core can install \(provider)'s app on \(i.runner), "
            + "then the sign-in goes on here."
    }

    private func progress(_ i: Install) -> some View {
        let p = i.progress
        let installingNow = p?.state == .running
        return VStack(alignment: .leading, spacing: Space.s2) {
            if installingNow, let p {
                CoreMeter(
                    Double(p.percent) / 100, height: ConnectWizardWords.barHeight, label: "Installing \(provider)")
            } else {
                CoreBusyBar()
            }
            Text(
                installingNow
                    ? ConnectWizardWords.installing(on: i.runner, percent: p?.percent ?? 0)
                    : i.waiting
                        ? "Installed. Waiting for \(i.runner) to restart with it…"
                        : "Starting the install on \(i.runner)…"
            )
            .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
        }
        .accessibilityIdentifier("no-runner-install")
    }
}

/// Where the account's login lives: "Signed in on the Core · works on every runner", or "Runs only on <runner>".
struct RunnerBoundNote: View {
    let binding: RunnerBinding
    var body: some View {
        Label(binding.words, systemImage: binding.core ? "checkmark.shield" : "server.rack")
            .coreFont(size: MacTextSize.meta)
            .foregroundStyle(GlassInk.secondary).help(binding.detail)
            .accessibilityHint(binding.detail)
    }
}
