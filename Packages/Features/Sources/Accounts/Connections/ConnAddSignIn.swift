import AppKit
import CoreUI
import SwiftUI

/// Step 2 (sign in) and step 5 (done) of the guided Add.
extension ConnAddView {
    // MARK: 2. sign in

    @ViewBuilder var signInStep: some View {
        switch model.flow?.step {
        case .failed(let title, let fix)?: failedStep(title, fix)
        case .pickSite(let sites)?: checklistStep(sites: sites)
        default: checklistStep(sites: nil)
        }
    }

    /// The checklist is read from the real flow (`ConnSignIn`): it ticks when the app knows, never on a timer.
    private func checklistStep(sites: [String]?) -> some View {
        let items = ConnSignIn.items(kind: kind, flow: model.flow, copied: copied)
        let waiting = sites == nil
        let chosen = site ?? sites?.first
        return VStack(spacing: Space.s4) {
            ConnPair(kind: a.kind ?? "")
            head(
                a.again ? "Sign in again on \(name)" : "Sign in on \(name)",
                "Three quick steps in your browser. This window moves on by itself.")
            VStack(spacing: Space.s2) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    checkRow(i + 1, item, sites: sites, chosen: chosen)
                }
            }
            if waiting { CoreWorkingBar(width: 600 - 2 * Space.s6) }
            if sites == nil {
                footer()
            } else {
                footer(primary: ("Use this site", { Task { await model.choose(site: chosen) } }))
            }
        }
    }

    @ViewBuilder private func checkRow(_ n: Int, _ item: ConnSignInItem, sites: [String]?, chosen: String?)
        -> some View
    {
        let detail: AnyView? = item.role == .copy ? codeLine : nil
        ConnCheckRow(index: n, item: item, detail: detail, trailing: trailing(item))
        if item.role == .pick, let sites {
            VStack(spacing: Space.s1) {
                ForEach(sites, id: \.self) { s in siteButton(s, chosen: s == chosen) }
            }
        }
    }

    @ViewBuilder private func trailing(_ item: ConnSignInItem) -> some View {
        switch item.role {
        case .copy:
            if let code = model.flow?.userCode {
                Button(copied ? "Copied" : "Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    copied = true
                }
                .buttonStyle(CoreButtonStyle(.secondary, size: .small)).help("Copy the code")
            }
        case .open:
            if item.state != .done {
                Button("Open again") { model.openSignIn() }
                    .buttonStyle(CoreButtonStyle(.secondary, size: .small)).help("Open \(name) in your browser again")
            }
        case .pick, .approve: EmptyView()
        }
    }

    /// The device code, big and selectable, under "Copy this code".
    private var codeLine: AnyView? {
        guard let code = model.flow?.userCode else { return nil }
        return AnyView(
            Text(code).coreFont(size: MacTextSize.large, weight: .semibold, design: .monospaced)
                .textSelection(.enabled)
                .accessibilityLabel("Code \(code.map(String.init).joined(separator: " "))"))
    }

    /// Jira with several sites: the Core needs one chosen.
    private func siteButton(_ s: String, chosen: Bool) -> some View {
        Button {
            site = s
        } label: {
            HStack {
                Text(s)
                Spacer()
                if chosen { Image(systemName: "checkmark").foregroundStyle(GlassInk.accent(paneAccent)) }
            }
            .padding(Space.s3).background(GlassInk.well, in: coreShape(Radius.cardMac))
            .contentShape(coreShape(Radius.cardMac))
        }
        .buttonStyle(CoreQuietPressStyle(radius: Radius.cardMac, hoverFill: true))
    }

    private func failedStep(_ title: String, _ fix: String) -> some View {
        let gated = model.flow?.gated == true
        let notSet = fix == ConnSay.notConfigured
        return VStack(spacing: Space.s3) {
            IconTile("exclamationmark.triangle", hue: GlassInk.red, size: 56, bounce: false)
            Text("Sign-in didn't finish").coreFont(size: MacTextSize.large, weight: .semibold)
                .accessibilityAddTraits(.isHeader)
            Text(
                title == ConnSay.expiredTitle
                    ? "We didn't hear back from \(name). Nothing was connected." : "\(title) \(fix)"
            )
            .foregroundStyle(GlassInk.secondary).multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            if gated { TurnOnConnections(model: model) { model.retrySignIn() } }
            HStack(spacing: Space.s2) {
                if notSet, let k = kind {
                    AccLink(title: "Set up your own app", symbol: "gearshape") { ConnDialogs.openApp(model, k) }
                }
                if let k = kind, !k.tokenTitle.isEmpty, !a.again {
                    AccLink(title: "Use a token instead", symbol: "key") { token = true }
                }
            }
            footer(primary: ("Try again", { model.retrySignIn() }))
        }
    }

    // MARK: 5. done

    var doneStep: some View {
        let title = a.again ? "\(name) is signed in again" : a.editing ? "Saved" : "\(name) is connected"
        return VStack(spacing: Space.s3) {
            ConnArrival(kind: a.kind ?? "").padding(.bottom, Space.s2)
            Text(title).coreFont(size: MacTextSize.large, weight: .semibold).accessibilityAddTraits(.isHeader)
            Text(a.again ? "Nothing else changed." : a.doneLine(noun: kind?.resource ?? "places"))
                .foregroundStyle(GlassInk.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            // Two plain footers, not `cond ? nil : CoreAction(...)`: the Done scene once crashed copying a bad reference out
            // of this step's view value (objc_retain), and the same ternary also crashed the Swift 6.4 type checker.
            if a.editing || a.again {
                CoreDialogFooter(cancel: nil, primary: CoreAction("Done", key: .primary, run: close))
                    .padding(.top, Space.s2)
            } else {
                CoreDialogFooter(
                    cancel: CoreAction("Connect Another") { model.addAnother() },
                    primary: CoreAction("Done", key: .primary, run: close)
                )
                .padding(.top, Space.s2)
            }
        }
    }
}

/// The service's logo slides into the Core tile and a check pops on it. Reduce Motion shows the end state.
struct ConnArrival: View {
    let kind: String
    @State private var arrived = false
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        let done = arrived || reduce
        ZStack(alignment: .bottomTrailing) {
            ConnCoreTile(size: 72)
            ConnLogo(kind: kind, size: 72, lit: true)
                .offset(x: done ? 0 : -88)  // grid: ok motion only, the logo travelling in
                .scaleEffect(done ? 0.6 : 1)
                .opacity(done ? 0 : 1)
            ZStack {
                coreShape(Radius.control).fill(GlassInk.green)
                Image(systemName: "checkmark").coreFont(size: MacTextSize.body, weight: .bold).foregroundStyle(.white)
            }
            .frame(width: 28, height: 28)
            .scaleEffect(done ? 1 : 0.4)
            .opacity(done ? 1 : 0)
            .offset(x: Space.s2, y: Space.s2)  // grid: ok badge sits on the tile corner
            .animation(Motion.press(Motion.move).delay(reduce ? 0 : 0.3), value: done)
        }
        .animation(Motion.calm(Motion.out(Motion.reveal), reduce), value: done)
        .onAppear { arrived = true }
        .accessibilityHidden(true)
    }
}
