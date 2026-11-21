import AppKit
import CoreUI
import SwiftUI

/// The guided Add (D-21, mockup 10): service tiles, sign in on the service's own website with a live waiting state, what
/// AI may do, which repositories (or projects, teams, channels), done. The same dialog opens on step 3 or 4 from a row's
/// More menu. All moves live in `ConnAddState`; this only draws them.
struct ConnAddView: View {
    @Environment(\.coreAccent) private var paneAccent
    let model: ConnectionsModel
    let close: () -> Void
    @State private var token = false
    @State private var site: String?
    @Environment(\.accessibilityReduceMotion) private var reduce

    private var a: ConnAddState { model.add ?? ConnAddState() }
    private var kind: ConnKind? { a.kind.flatMap(model.kind) }
    private var name: String { kind?.name ?? "the service" }

    var body: some View {
        Group {
            if token, let k = kind {
                TokenForm(model: model, kind: k, back: { token = false }, close: close)
            } else {
                panel
            }
        }
        .accessibilityIdentifier("connection-connect")
    }

    private var panel: some View {
        CoreDialogPanel("", width: 780) {
            VStack(spacing: Space.s2) {
                ConnSteps(at: a.step)
                stage
                    .id(a.step)
                    .transition(.opacity)
                    .frame(maxWidth: .infinity, minHeight: 332, alignment: .top)
            }
            .animation(reduce ? nil : .smooth(duration: 0.34), value: a.step)
        }
    }

    @ViewBuilder private var stage: some View {
        switch a.step {
        case .service: serviceStep
        case .signIn: signInStep
        case .allow: allowStep
        case .choose: chooseStep
        case .done: doneStep
        }
    }

    private func head(_ title: String, _ sub: String) -> some View {
        VStack(spacing: Space.s1 / 2) {
            Text(title).coreFont(size: MacTextSize.large, weight: .semibold).multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(sub).foregroundStyle(GlassInk.secondary).multilineTextAlignment(.center)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func back() -> CoreAction { CoreAction("Back") { model.addBack() } }

    // MARK: 1. pick a service

    private var serviceStep: some View {
        VStack(spacing: Space.s3) {
            head("Connect a service", "Pick one. You sign in on its own website, never here.")
            ConnTiles(kinds: model.kinds) { model.pick(service: $0) }.padding(.top, Space.s2)
            Spacer(minLength: Space.s3)
            CoreDialogFooter(cancel: CoreAction("Cancel", key: .cancel, run: close), primary: nil)
        }
    }

    // MARK: 2. sign in

    @ViewBuilder private var signInStep: some View {
        switch model.flow?.step {
        case .failed(let title, let fix)?: failedStep(title, fix)
        case .pickSite(let sites)?: siteStep(sites)
        default: waitingStep
        }
    }

    private var waitingStep: some View {
        VStack(spacing: Space.s3) {
            HStack(spacing: Space.s5) {
                ConnLogo(kind: a.kind ?? "", size: 72).connFloat()
                ConnLink()
                IconTile("link", hue: GlassInk.accent(paneAccent), size: 72, bounce: false).connFloat(
                    phase: ConnMotion.heroPhase)
            }
            .padding(.top, Space.s6)
            head(
                "Finish signing in on \(name)", "We opened \(name) in your browser. Sign in there, then come back here."
            )
            if let code = model.flow?.userCode { codeBox(code) }
            HStack(spacing: Space.s3) {
                CoreWorkingBar(width: Space.s8 * 4 + Space.s3)
                Text("Waiting for \(name)…").foregroundStyle(GlassInk.secondary)
            }
            Spacer(minLength: Space.s3)
            CoreDialogFooter(
                cancel: back(), primary: nil,
                alternate: CoreAction("Open \(name) again") { model.openSignIn() })
        }
    }

    /// A device-code sign-in (GitHub, Teams) asks for this code on the service's page.
    private func codeBox(_ code: String) -> some View {
        VStack(spacing: Space.s1) {
            Text("Type this code on the page that opened").coreFont(size: MacTextSize.meta)
                .foregroundStyle(GlassInk.secondary)
            Text(code).coreFont(size: MacTextSize.large + 8, weight: .semibold, design: .monospaced)
                .textSelection(.enabled)
                .accessibilityLabel("Code \(code.map(String.init).joined(separator: " "))")
            Button("Copy code") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(code, forType: .string)
            }
            .buttonStyle(CoreButtonStyle(.secondary, size: .small))
        }
        .padding(.vertical, Space.s3).padding(.horizontal, Space.s5)
        .background(GlassInk.well, in: coreShape(Radius.cardMac))
    }

    private func failedStep(_ title: String, _ fix: String) -> some View {
        let gated = model.flow?.gated == true
        let notSet = fix == ConnSay.notConfigured
        return VStack(spacing: Space.s2) {
            IconTile("exclamationmark.triangle", hue: GlassInk.red, size: 72, bounce: false).padding(.top, Space.s6)
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
            Spacer(minLength: Space.s3)
            CoreDialogFooter(cancel: back(), primary: CoreAction("Try again", key: .primary) { model.retrySignIn() })
        }
    }

    /// Jira with several sites: not in the mockup, but the Core needs one chosen.
    private func siteStep(_ sites: [String]) -> some View {
        let chosen = site ?? sites.first
        return VStack(spacing: Space.s3) {
            head("Which \(name) site?", "You have more than one. Connect the other later if you need it.")
            VStack(spacing: Space.s1) {
                ForEach(sites, id: \.self) { s in
                    Button {
                        site = s
                    } label: {
                        HStack {
                            Text(s)
                            Spacer()
                            if s == chosen {
                                Image(systemName: "checkmark").foregroundStyle(GlassInk.accent(paneAccent))
                            }
                        }
                        .padding(Space.s3).background(GlassInk.well, in: coreShape(Radius.cardMac))
                        .contentShape(coreShape(Radius.cardMac))
                    }
                    .buttonStyle(CoreQuietPressStyle(radius: Radius.cardMac, hoverFill: true))
                }
            }
            Spacer(minLength: Space.s3)
            CoreDialogFooter(
                cancel: back(),
                primary: CoreAction("Use this site", key: .primary) { Task { await model.choose(site: chosen) } })
        }
    }

    // MARK: 3. what may it do

    private var allowStep: some View {
        let mode = Binding(get: { a.mode }, set: { model.add?.set(mode: $0, in: kind) })
        return VStack(spacing: Space.s3) {
            head("What may your assistant do on \(name)?", "Start safe. You can change this any time.")
            CoreSegmented(
                "What it may do",
                segments: [
                    CoreSegment(ConnMode.read, "Read only", symbol: "eye"),
                    CoreSegment(ConnMode.write, "Read and change", symbol: "bolt"),
                ], selection: mode)
            VStack(spacing: Space.s1 + 2) {
                ForEach(kind?.capabilities ?? []) { c in capability(c) }
            }
            if a.mode == .write {
                Label(
                    "It will be able to change things on \(name) as you. Saving needs Touch ID.",
                    systemImage: "exclamationmark.triangle"
                )
                .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.amberInk)
            }
            Spacer(minLength: Space.s3)
            CoreDialogFooter(
                cancel: a.editing ? CoreAction("Cancel", key: .cancel, run: close) : back(),
                primary: CoreAction("Next", key: .primary) { model.addNext() })
        }
    }

    private func capability(_ c: ConnCapability) -> some View {
        let on = Binding(get: { a.isOn(c) }, set: { _ in model.add?.toggle(c.id) })
        let dim = c.writes && a.mode == .read
        return HStack(spacing: Space.s3) {
            IconTile(
                c.writes ? "bolt" : "eye", hue: c.writes ? GlassInk.amber : GlassInk.green, size: 32,
                bounce: on.wrappedValue)
            VStack(alignment: .leading, spacing: 0) {
                Text(c.title).coreFont(size: MacTextSize.body, weight: .semibold)
                Text(c.say).coreFont(size: MacTextSize.meta + 1).foregroundStyle(GlassInk.secondary)
            }
            Spacer(minLength: Space.s3)
            CoreSwitch("", isOn: on).disabled(!c.writes || a.mode == .read)
                .accessibilityLabel(c.title)
        }
        .padding(.horizontal, Space.s4).padding(.vertical, Space.s3)
        .background(GlassInk.well, in: coreShape(Radius.cardMac))
        .opacity(dim ? 0.55 : 1)
    }

    // MARK: 4. which ones

    private var chooseStep: some View {
        let noun = kind?.resource ?? "places"
        let query = Binding(get: { a.query }, set: { model.add?.query = $0 })
        let saving = model.busy?.hasPrefix("access-") == true
        return VStack(spacing: Space.s2 + 2) {
            head("Which \(noun)?", "Your assistant only sees the ones you pick.")
            HStack(spacing: Space.s2) {
                Image(systemName: "magnifyingglass").foregroundStyle(GlassInk.secondary).accessibilityHidden(true)
                TextField("Search \(noun)", text: query).textFieldStyle(.plain)
            }
            .coreFieldSurface()
            pickList(noun)
            if let e = model.addError { AccIssue(text: e) }
            if let c = a.connection, model.gated.contains("access-\(c)") {
                TurnOnConnections(model: model) { await model.finishAdd() }
            }
            Spacer(minLength: Space.s2)
            HStack(spacing: Space.s2) {
                Button("Back") { model.addBack() }.buttonStyle(CoreButtonStyle(.secondary))
                Text(a.countLine).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                    .padding(.leading, Space.s2)
                Spacer(minLength: Space.s3)
                Button(saving ? "Saving…" : (a.editing ? "Save" : "Connect \(name)")) {
                    Task { await model.finishAdd() }
                }
                .buttonStyle(CoreButtonStyle(.prominent, busy: saving)).coreShortcut(.primary)
                .disabled(!a.canFinish || saving)
            }
        }
    }

    @ViewBuilder private func pickList(_ noun: String) -> some View {
        switch model.picks {
        case .idle, .loading:
            VStack(spacing: Space.s1 + 2) {
                ForEach(0..<3, id: \.self) { _ in
                    CoreSkeleton(coreShape(Radius.control)).frame(height: Space.s8 + Space.s2)
                }
            }
            .accessibilityLabel("Loading \(noun)")
        case .failed(let why):
            CoreNotice(symbol: "exclamationmark.triangle", title: "Couldn't read your \(noun)", text: why, tone: .fail)
            {
                Button("Try again") { Task { await model.loadPicks() } }.buttonStyle(CoreButtonStyle(.secondary))
            }
        case .ready(let p):
            let rows = a.visible(p.items)
            if rows.isEmpty {
                Text(p.items.isEmpty ? "There is nothing to choose yet." : "No \(noun) match.")
                    .foregroundStyle(GlassInk.secondary).frame(maxWidth: .infinity).padding(.vertical, Space.s6)
            } else {
                ScrollView {
                    VStack(spacing: Space.s1 + 2) {
                        ForEach(rows) { r in
                            CoreCheckbox(
                                r.name, detail: ConnAccess.line(r),
                                isOn: Binding(
                                    get: { a.picked.contains(r.id) }, set: { _ in model.add?.toggle(pick: r.id) }),
                                // the mockup: folder for GitHub, doc for the rest
                                icon: a.kind == "github" ? "folder" : "doc.text"
                            )
                            .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(GlassInk.well, in: coreShape(Radius.control))
                        }
                    }
                }
                .scrollIndicators(.never).frame(maxHeight: 196)
                if p.truncated {
                    Text("There are more. Type in the search to narrow the list.").coreFont(size: MacTextSize.meta)
                        .foregroundStyle(GlassInk.secondary)
                }
            }
        }
    }

    // MARK: 5. done

    private var doneStep: some View {
        let title = a.again ? "\(name) is signed in again" : a.editing ? "Saved" : "\(name) is connected"
        return VStack(spacing: Space.s2) {
            IconTile("checkmark", hue: GlassInk.green, size: 72, bounce: a.step).connFloat().padding(.top, Space.s6)
            Text(title).coreFont(size: MacTextSize.large, weight: .semibold).accessibilityAddTraits(.isHeader)
            Text(a.again ? "Nothing else changed." : a.doneLine(noun: kind?.resource ?? "places"))
                .foregroundStyle(GlassInk.secondary).multilineTextAlignment(.center)
            Spacer(minLength: Space.s3)
            CoreDialogFooter(
                cancel: a.editing || a.again ? nil : CoreAction("Connect another") { model.addAnother() },
                primary: CoreAction("Done", key: .primary, run: close))
        }
    }
}
