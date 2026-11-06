import CoreUI
import SwiftUI

/// Connect a Claude plan (KAN-441): you confirm it is your own plan, Core starts Claude's own sign-in on a runner, your
/// browser opens claude.ai, you paste the short code Claude shows, and the account appears. The app never sees a
/// token: the runner hands it straight to Core. Every stage is keyboard driven (↩ goes on, esc stops).
struct SubscriptionSignIn: View {
    let model: AccountsModel
    let provider: ProviderItem
    let close: () -> Void
    @State private var label = "claude-plan"
    @State private var ack = false
    @State private var code = ""
    @State private var advanced = false
    @State private var runners: [AccountRunner] = []
    @State private var runner: String?

    private var hue: Color { ProviderLook.hue(provider.id) }
    private var labelOK: Bool { label.range(of: "^[a-z][a-z0-9._-]{0,63}$", options: .regularExpression) != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            StepTrack(["Confirm", "Sign in", "Done"], at: step, hue: hue)
            Group {
                switch model.signIn?.stage {
                case nil: intro
                case .starting?: waiting("Getting Claude ready", "Starting Claude's sign-in on a runner…")
                case .open(let url)?: signIn(url)
                case .working?: waiting("Almost there", "Connecting your Claude plan to your Core…")
                case .done(let account)?: done(account)
                case .failed(let why)?: failed(why)
                }
            }
            .transition(.opacity.combined(with: .move(edge: .trailing)))
        }
        .animation(Motion.out(Motion.move), value: model.signIn)
        .accessibilityIdentifier("subscription-sign-in")
    }

    private var step: Int {
        switch model.signIn?.stage {
        case nil: 0
        case .done?: 2
        default: 1
        }
    }

    // MARK: stages

    private var intro: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text(
                "Sign in with your Claude Pro or Max plan. You sign in on claude.ai; Ainkrad never sees your password."
            )
            .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
            GlassToggleTile(
                "This is my own Claude plan, for my own use.",
                sub: "Anthropic's terms don't allow sharing a plan or using someone else's.", symbol: "person",
                onSymbol: "person.fill.checkmark", isOn: $ack, fill: true)
            CoreTextField(
                "Name", placeholder: "claude-plan", text: $label,
                error: labelOK || label.isEmpty
                    ? nil : "Lowercase letters, digits and . _ -, starting with a letter.", mono: true)
            HStack(spacing: Space.s2) {
                Label(
                    runner.flatMap { r in runners.first { $0.id == r }?.name }.map { "Claude's sign-in runs on \($0)." }
                        ?? "Claude's sign-in runs on your best ready runner.", systemImage: "server.rack"
                )
                .font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary)
                Spacer(minLength: 0)
                AccLink(title: advanced ? "Hide" : "Pick a runner", symbol: advanced ? "chevron.up" : "chevron.down") {
                    withAnimation(Motion.out(Motion.move)) { advanced.toggle() }
                }
            }
            if advanced { runnerPicker.transition(.opacity.combined(with: .move(edge: .top))) }
            CoreDialogFooter(confirm: "Sign in with Claude", enabled: ack && labelOK, cancel: close) {
                Task { await model.startSignIn(provider: provider.id, label: label, runner: runner) }
            }
        }
    }

    /// Automatic first, then each runner; one that is offline can't be picked.
    private var runnerPicker: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: Space.s2)], spacing: Space.s2) {
            AccPick(title: "Automatic", sub: "Best ready runner", symbol: "bolt", hue: hue, on: runner == nil) {
                runner = nil
            }
            ForEach(runners) { r in
                AccPick(
                    title: r.name, sub: r.online ? "Online" : "Offline", symbol: "server.rack", hue: hue,
                    on: runner == r.id, enabled: r.online
                ) { runner = r.id }
            }
        }
        .task {
            guard runners.isEmpty, let svc = model.service else { return }
            runners = (try? await svc.runners()) ?? []
        }
    }

    private func signIn(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            numbered(1, "Sign in on claude.ai", "Your browser opened claude.ai. Sign in and allow access.") {
                AppActionTile(title: "Open Claude again", symbol: "arrow.up.right.square", key: "⌘O", hue: hue) {
                    model.opener(url)
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            numbered(2, "Paste the code Claude shows you", "It's a short code, not a password.") {
                CoreTextField(
                    "Code", placeholder: "Paste the code here", text: $code, mono: true, autofocus: true,
                    onSubmit: send
                )
                .accessibilityIdentifier("sign-in-code")
                if let e = model.signIn?.codeError { AccIssue(text: e) }
            }
            CoreDialogFooter(
                confirm: "Connect", enabled: !code.trimmingCharacters(in: .whitespaces).isEmpty,
                cancel: {
                    Task {
                        await model.cancelSignIn()
                        close()
                    }
                }, run: send)
        }
    }

    private func send() { Task { await model.sendSignInCode(code) } }

    private func waiting(_ title: String, _ line: String) -> some View {
        VStack(spacing: Space.s3) {
            IconTile("person.badge.clock", hue: hue, size: Space.s8 * 2)
            Text(title).font(.system(size: MacTextSize.large, weight: .semibold))
            Text(line).foregroundStyle(GlassInk.secondary).multilineTextAlignment(.center)
            AccBar().frame(maxWidth: Space.s8 * 6)
            AppActionTile(title: "Stop", symbol: "xmark", key: "esc", hue: GlassInk.slate) {
                Task {
                    await model.cancelSignIn()
                    close()
                }
            }
            .keyboardShortcut(.cancelAction)
        }
        .frame(maxWidth: .infinity).padding(.vertical, Space.s4)
    }

    private func done(_ account: Int64?) -> some View {
        VStack(spacing: Space.s3) {
            IconTile("checkmark.seal.fill", hue: GlassInk.green, size: Space.s8 * 2, bounce: account)
            Text("Your Claude plan is connected").font(.system(size: MacTextSize.large, weight: .semibold))
            Text(
                "It's saved in your Core as \(model.signIn?.label ?? "your plan"). Put it in a pool of its own so agents can use it."
            )
            .foregroundStyle(GlassInk.secondary).multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            CoreDialogFooter(confirm: "Open the account", cancelTitle: "Close", cancel: finish) {
                let id = account
                finish()
                if let id {
                    model.page = .accounts
                    model.detail = id
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func failed(_ why: String) -> some View {
        VStack(spacing: Space.s3) {
            IconTile("exclamationmark.triangle.fill", hue: GlassInk.red, size: Space.s8 * 2, bounce: true)
            Text("Couldn't connect Claude").font(.system(size: MacTextSize.large, weight: .semibold))
            Text(why).foregroundStyle(GlassInk.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true).help(model.signIn?.reason ?? "")
            CoreDialogFooter(confirm: "Try again", cancelTitle: "Close", cancel: finish) { model.signIn = nil }
        }
        .frame(maxWidth: .infinity)
    }

    private func finish() {
        model.signIn = nil
        close()
    }

    private func numbered<C: View>(_ n: Int, _ title: String, _ line: String, @ViewBuilder _ c: () -> C) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "\(n).square.fill").font(.system(size: MacTextSize.large, weight: .semibold))
                .foregroundStyle(hue)
            VStack(alignment: .leading, spacing: Space.s2) {
                Text(title).font(.system(size: MacTextSize.headline, weight: .semibold))
                Text(line).foregroundStyle(GlassInk.secondary)
                c()
            }
        }
    }
}
