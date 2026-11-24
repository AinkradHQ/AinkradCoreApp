import AppKit
import CoreUI
import SwiftUI

/// The guided Add (D-21): service cards, sign in on the service's own website with a checklist that follows the real
/// sign-in, what AI may do, which repositories (or projects, teams, channels), done. The same dialog opens on step 3 or 4
/// from a row's More menu. All moves live in `ConnAddState`; this only draws them. The dialog is as tall as its step.
struct ConnAddView: View {
    @Environment(\.coreAccent) var paneAccent
    let model: ConnectionsModel
    let close: () -> Void
    @State var token = false
    @State var site: String?
    @State var copied = false
    @Environment(\.accessibilityReduceMotion) var reduce

    var a: ConnAddState { model.add ?? ConnAddState() }
    var kind: ConnKind? { a.kind.flatMap(model.kind) }
    var name: String { kind?.name ?? "the service" }

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
        CoreDialogPanel("", width: 600) {
            VStack(spacing: Space.s5) {
                ConnSteps(at: a.step)
                ConnStage(step: a.step) { stage }
            }
        }
        // The height eases between steps (and as a sign-in moves on); Reduce Motion fades instead.
        .animation(Motion.calm(Motion.out(Motion.move), reduce), value: a.step)
        .animation(Motion.calm(Motion.out(Motion.move), reduce), value: model.flow?.step)
        .animation(Motion.calm(Motion.out(Motion.ui), reduce), value: a.mode)
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

    func head(_ title: String, _ sub: String) -> some View {
        VStack(spacing: Space.s1) {
            Text(title).coreFont(size: MacTextSize.large, weight: .semibold).multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(sub).foregroundStyle(GlassInk.secondary).multilineTextAlignment(.center)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Cancel on the left, Back beside it when the step has a way back.
    func footer(
        back: Bool = true, alternate: (String, () -> Void)? = nil, primary: (String, () -> Void)? = nil,
        enabled: Bool = true, busy: Bool = false
    ) -> some View {
        ConnFooter(
            cancel: close, back: back && a.canGoBack ? { model.addBack() } : nil, alternate: alternate,
            primary: primary, enabled: enabled, busy: busy)
    }

    // MARK: 1. pick a service

    private var serviceStep: some View {
        VStack(spacing: Space.s4) {
            head("Connect a service", "Pick one. You sign in on its own website, never here.")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.s2), count: 3), spacing: Space.s2)
            {
                ForEach(model.kinds) { k in ConnPickCard(kind: k) { model.pick(service: k.id) } }
            }
            footer(back: false)
        }
    }

    // MARK: 3. what may it do

    private var allowStep: some View {
        let mode = Binding(get: { a.mode }, set: { model.add?.set(mode: $0, in: kind) })
        return VStack(spacing: Space.s4) {
            ConnPair(kind: a.kind ?? "", size: 56)
            head("What may your assistant do on \(name)?", "You can change this any time in Connections.")
            CoreSegmented(
                "What it may do",
                segments: [
                    CoreSegment(ConnMode.read, "Read only", symbol: "eye"),
                    CoreSegment(ConnMode.write, "Read and change", symbol: "bolt"),
                ], selection: mode)
            VStack(spacing: Space.s1) {
                ForEach(kind?.capabilities ?? []) { c in capability(c) }
            }
            if a.mode == .write {
                Label(
                    "It will be able to change things on \(name) as you. Saving needs Touch ID.",
                    systemImage: "exclamationmark.triangle"
                )
                .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.amberInk)
            } else {
                Text("Recommended to start. It can look, never touch.").coreFont(size: MacTextSize.meta)
                    .foregroundStyle(GlassInk.secondary)
            }
            footer(primary: ("Continue", { model.addNext() }))
        }
    }

    private func capability(_ c: ConnCapability) -> some View {
        let on = Binding(get: { a.isOn(c) }, set: { _ in model.add?.toggle(c.id) })
        let dim = c.writes && a.mode == .read
        return HStack(spacing: Space.s3) {
            Image(systemName: ConnLook.capabilitySymbol(c)).coreFont(size: MacTextSize.body, weight: .medium)
                .foregroundStyle(dim ? GlassInk.secondary : GlassInk.primary)
                .frame(width: 28, height: 28).background(GlassInk.well, in: coreShape(Radius.control))
                .accessibilityHidden(true)
            Text(c.title).coreFont(size: MacTextSize.body, weight: .medium)
                .foregroundStyle(dim ? GlassInk.secondary : GlassInk.primary)
            Spacer(minLength: Space.s3)
            if c.writes {
                CoreSwitch("", isOn: on).disabled(a.mode == .read).accessibilityLabel(c.title)
            } else {
                StateBadge("Always", tone: .done, symbol: "checkmark.circle")
            }
        }
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(c.say)
        .opacity(dim ? 0.7 : 1)
    }

    // MARK: 4. which ones

    private var chooseStep: some View {
        let noun = kind?.resource ?? "places"
        let query = Binding(get: { a.query }, set: { model.add?.query = $0 })
        let saving = model.busy?.hasPrefix("access-") == true
        var rows: [ConnPick] = []
        if case .ready(let p) = model.picks { rows = a.visible(p.items) }
        let all = a.allPicked(rows)
        return VStack(spacing: Space.s3) {
            head("Which \(noun)?", "Your assistant only sees what you tick.")
            HStack(spacing: Space.s2) {
                HStack(spacing: Space.s2) {
                    Image(systemName: "magnifyingglass").foregroundStyle(GlassInk.secondary).accessibilityHidden(true)
                    TextField("Search \(noun)", text: query).textFieldStyle(.plain)
                }
                .coreFieldSurface()
                Button(all ? "Clear All" : "Select All") {
                    if all { model.add?.clearAll(rows) } else { model.add?.selectAll(rows) }
                }
                .buttonStyle(CoreButtonStyle(.secondary)).disabled(rows.isEmpty)
            }
            pickList(noun)
            if let e = model.addError { AccIssue(text: e) }
            if let c = a.connection, model.gated.contains("access-\(c)") {
                TurnOnConnections(model: model) { await model.finishAdd() }
            }
            footer(
                primary: (a.finishTitle(noun: noun, saving: saving), { Task { await model.finishAdd() } }),
                enabled: a.canFinish && !saving, busy: saving)
        }
    }

    @ViewBuilder private func pickList(_ noun: String) -> some View {
        switch model.picks {
        case .idle, .loading:
            VStack(spacing: Space.s1) {
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
                    VStack(spacing: Space.s1) {
                        ForEach(rows) { r in
                            let on = a.picked.contains(r.id)
                            CoreCheckbox(
                                r.name, detail: ConnAccess.line(r),
                                isOn: Binding(get: { on }, set: { _ in model.add?.toggle(pick: r.id) })
                            )
                            .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(on ? GlassInk.wellHover : GlassInk.well, in: coreShape(Radius.control))
                            .animation(Motion.out(Motion.hover), value: on)
                        }
                    }
                }
                .scrollIndicators(.never).frame(maxHeight: 232)
                if p.truncated {
                    Text("There are more. Type in the search to narrow the list.").coreFont(size: MacTextSize.meta)
                        .foregroundStyle(GlassInk.secondary)
                }
            }
        }
    }
}
