import CoreUI
import SwiftUI

/// The runner's own sign-in as text (OpenCode, Antigravity): a read-only screen in a well, one line to type and Send. The
/// text is redacted by the runner and the Core; it is shown here and never kept. A sent line is cleared at once and never
/// echoed back.
struct GuidedTerminal: View {
    let lines: [String]
    let error: String?
    var provider = ""
    let sending: Bool
    let send: (String) -> Void
    @State private var line = ""
    /// "This is a secret": the line is typed into a secure field, so it is never shown. Off for each new sign-in.
    @State private var secret = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            screen
            HStack(alignment: .bottom, spacing: Space.s2) {
                Group {
                    if secret {
                        CoreSecureField("", placeholder: "Type it, then press Return", text: $line, error: error) {
                            go()
                        }
                    } else {
                        CoreTextField(
                            "", placeholder: "Type a line, then press Return", text: $line, error: error, mono: true
                        ) {
                            go()
                        }
                    }
                }
                .accessibilityIdentifier("guided-input")
                Button("Send", action: go).buttonStyle(CoreButtonStyle(.secondary))
                    .disabled(sending || line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("guided-send")
            }
            Text(provider == "agy-sub" ? GuidedInput.agyHint : GuidedInput.hint).coreFont(size: MacTextSize.meta)
                .foregroundStyle(GlassInk.secondary)
                .fixedSize(horizontal: false, vertical: true)
            CoreCheckbox("This is a secret", isOn: $secret).accessibilityIdentifier("guided-secret")
        }
    }

    private func go() {
        let l = line
        line = ""
        send(l)
    }

    private var screen: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if lines.isEmpty {
                        Text("Waiting for the runner…").foregroundStyle(GlassInk.secondary)
                    }
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, l in
                        Text(l.isEmpty ? " " : l).coreFont(size: MacTextSize.meta, design: .monospaced)
                            .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(Space.s3)
            }
            .scrollIndicators(.never)
            .onChange(of: lines) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
        }
        .frame(height: Space.s8 * 4)
        .coreWell(radius: Radius.control)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sign-in screen")
        .accessibilityIdentifier("guided-screen")
    }
}

/// Which runner the account will live on, when more than one can sign in. Online runners only; the first is picked.
struct RunnerPickView: View {
    @Environment(\.coreAccent) private var paneAccent
    let provider: String
    let choice: RunnerChoice
    let pick: (String) -> Void
    /// Set for Codex and Antigravity: the risk note is agreed to here, before the sign-in starts.
    var consent: Binding<Bool>?
    let start: () -> Void
    let back: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VStack(spacing: Space.s2) {
                ProviderTile(name: provider, size: Space.s8 * 2)
                Text("Choose a runner").coreFont(size: MacTextSize.large, weight: .bold)
                Text("\(provider) signs in on one runner. This account only runs there.")
                    .foregroundStyle(GlassInk.secondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: Space.s2)], spacing: Space.s2) {
                ForEach(choice.eligible) { r in
                    AccPick(
                        title: r.name, sub: "Online", symbol: "server.rack", hue: GlassInk.accent(paneAccent),
                        on: choice.selected == r.id
                    ) {
                        pick(r.id)
                    }
                }
            }
            if let consent {
                RiskConsent(agreed: consent)
            }
            AccDialogButtons(
                confirm: "Continue", cancelTitle: "Back",
                enabled: choice.chosen != nil && (consent?.wrappedValue ?? true),
                cancel: back, run: start)
        }
        .accessibilityIdentifier("runner-pick")
    }
}

/// The risk note, agreed to before the sign-in starts (the mockup's a9-risk line, as a checkbox).
struct RiskConsent: View {
    static let note = "Uses your subscription at your own risk. The provider's rules may not allow it."
    static let agree = "I understand this may break the provider's rules and is my own risk"
    @Binding var agreed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Label(Self.note, systemImage: "exclamationmark.triangle").coreFont(size: MacTextSize.meta)
                .foregroundStyle(GlassInk.amberInk).fixedSize(horizontal: false, vertical: true)
            CoreCheckbox(Self.agree, isOn: $agreed)
                .accessibilityIdentifier("risk-consent")
        }
    }
}

/// No online runner can run this sign-in: say why and offer the real fix, never a button that does nothing.
struct NoRunnerView: View {
    let provider: String
    let choice: RunnerChoice
    let openRunners: () -> Void
    let back: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VStack(spacing: Space.s2) {
                ProviderTile(name: provider, size: Space.s8 * 2)
                Text("No runner can sign in yet").coreFont(size: MacTextSize.large, weight: .bold)
                Text(choice.why(provider: provider)).foregroundStyle(GlassInk.secondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            AccDialogButtons(confirm: "Open runners", cancelTitle: "Back", cancel: back, run: openRunners)
        }
        .accessibilityIdentifier("no-runner")
    }
}

/// "Runs only on <runner>": the line for an account pinned to one runner.
struct RunnerBoundNote: View {
    let binding: RunnerBinding
    var body: some View {
        Label(binding.words, systemImage: "server.rack").coreFont(size: MacTextSize.meta)
            .foregroundStyle(GlassInk.secondary).help(binding.detail)
            .accessibilityHint(binding.detail)
    }
}

/// "Waiting for you to finish…" as in the mockup: five small rounded squares that lift one after another. With Reduce Motion
/// they stand still, the first three lit.
struct WaitingDots: View {
    @Environment(\.coreAccent) private var paneAccent
    let text: String
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        HStack(spacing: Space.s3) {
            if reduce {
                dots { i in (i < 3 ? 1.0 : 0.3, 0.0) }
            } else {
                TimelineView(.animation) { t in
                    dots { i in
                        // 1.5 s loop, each square 0.18 s behind the last: up at 40 %, back down by 80 %.
                        let p = ((t.date.timeIntervalSinceReferenceDate - Double(i) * 0.18) / 1.5).truncatingRemainder(
                            dividingBy: 1)
                        let q = p < 0 ? p + 1 : p
                        let lift = q < 0.4 ? q / 0.4 : q < 0.8 ? 1 - (q - 0.4) / 0.4 : 0
                        return (0.3 + 0.7 * lift, -3 * lift)
                    }
                }
            }
            Text(text).foregroundStyle(GlassInk.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func dots(_ f: @escaping (Int) -> (Double, Double)) -> some View {
        HStack(spacing: 5) {
            ForEach(0..<5, id: \.self) { i in
                let (o, y) = f(i)
                coreShape(3).fill(GlassInk.accent(paneAccent)).frame(width: 8, height: 8).opacity(o).offset(y: y)
            }
        }
        .accessibilityHidden(true)
    }
}
