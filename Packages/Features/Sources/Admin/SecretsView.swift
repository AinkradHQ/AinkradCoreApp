import CoreUI
import Shell
import SwiftUI

/// Settings, Security, Secrets (N24): what your Core keeps, as sections with one row per secret. Values go in and never come
/// back. Arrows move the cursor row; ↩ lets a runner use it, E gives it a new value, ⌫ deletes it, ⌘N adds one.
struct SecretsSection: View {
    let admin: AdminModel
    @State private var cursor: String?
    @State private var query = ""
    @State private var runner: String?
    @State private var closed: Set<String> = []
    @FocusState private var focus: Bool

    var body: some View {
        let model = admin.secrets!
        AdminScreen(
            admin: admin, what: "Secrets",
            intro:
                "Values go in and never come back: nobody can show or copy them, not even you. Runners use them for a short time.",
            state: model.state,
            empty: ("No secrets yet", "Add a secret, then let a runner use it.", "key"),
            emptyAction: ("New secret…", { SecretDialogs.openNew(admin) }),
            retry: { Task { await model.reload() } }
        ) {
            VStack(alignment: .leading, spacing: Space.s4) {
                ModePanel(admin: admin, mode: model.mode)
                AdminNoticeBanner(notice: admin.host.elevationNotice)
                toolbar(model)
                let shown = model.items.filter { SecretWords.matches($0, query: query, runner: runner) }
                if shown.isEmpty {
                    Text("No secret matches.").foregroundStyle(GlassInk.secondary)
                }
                ForEach(
                    SecretSections.sections(shown, groups: model.groups, narrowed: !query.isEmpty || runner != nil)
                ) { section in
                    sectionView(section, model)
                }
            }
            .foregroundStyle(GlassInk.primary)
            .focusable().focused($focus).focusEffectDisabled()
            .onKeyPress(phases: .down) { keys($0, model) }
            .onChange(of: model.items.map(\.name), initial: true) { _, names in
                if !names.contains(cursor ?? "") { cursor = names.first }
            }
        }
        .task {
            await model.reload()
            focus = true
        }
        .accessibilityIdentifier("secrets")
    }

    private func toolbar(_ model: SecretsModel) -> some View {
        HStack(spacing: Space.s2) {
            CoreTextField("", placeholder: "Search secrets", text: $query).frame(maxWidth: Space.s8 * 8)
            Menu(runner.map(model.runnerName) ?? "All runners") {
                Button("All runners") { runner = nil }
                ForEach(model.runners) { r in Button(r.name) { runner = r.id } }
            }
            .fixedSize()
            Spacer(minLength: 0)
            AppActionTile(title: "New group", symbol: "folder.badge.plus", key: "", hue: GlassInk.slate) {
                SecretDialogs.openGroup(admin, nil)
            }
            .help("Keep related secrets together and give them to runners in one step")
            AppActionTile(title: "New secret", symbol: "plus", key: "⌘N", hue: GlassInk.orange, prominent: true) {
                SecretDialogs.openNew(admin)
            }
            .keyboardShortcut("n", modifiers: .command)
        }
    }

    private func sectionView(_ section: SecretSectionItem, _ model: SecretsModel) -> some View {
        let open = !closed.contains(section.id)
        return VStack(alignment: .leading, spacing: Space.s2) {
            Button {
                withAnimation(.smooth(duration: 0.25)) {
                    if open { closed.insert(section.id) } else { closed.remove(section.id) }
                }
            } label: {
                HStack(spacing: Space.s2) {
                    Image(systemName: open ? "chevron.down" : "chevron.right").frame(width: 14)
                    Image(systemName: section.symbol).foregroundStyle(GlassInk.orange)
                    Text(section.title).coreFont(size: MacTextSize.headline, weight: .semibold)
                    Text("\(section.items.count)").foregroundStyle(GlassInk.secondary)
                    if let g = section.group {
                        Text(
                            g.description.isEmpty ? SecretWords.usedBy(g.runners.map(model.runnerName)) : g.description
                        )
                        .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).focusable(false)
            .accessibilityLabel("\(section.title), \(section.items.count) secrets")
            .accessibilityValue(open ? "Expanded" : "Collapsed")
            if let g = section.group { groupBar(g, model) }
            if open {
                ForEach(section.items) { s in
                    SecretRow(admin: admin, model: model, secret: s, selected: cursor == s.name) {
                        cursor = s.name
                        focus = true
                    }
                    .transition(.opacity)
                }
            }
        }
    }

    /// A group's runners and its actions: edit, let a runner use all of it, delete.
    private func groupBar(_ g: SecretGroupItem, _ model: SecretsModel) -> some View {
        HStack(spacing: Space.s2) {
            Label(
                g.runners.isEmpty
                    ? "No runner yet" : "Runners: " + g.runners.map(model.runnerName).joined(separator: ", "),
                systemImage: "server.rack"
            )
            .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary).lineLimit(1)
            Spacer(minLength: 0)
            AccGroupLink(title: "Edit", symbol: "pencil") { SecretDialogs.openGroup(admin, g) }
            AccGroupLink(title: "Let a runner use all", symbol: "server.rack") {
                SecretDialogs.openGroupLease(admin, g)
            }
            .disabled(g.members.isEmpty || g.runners.isEmpty)
            AccGroupLink(title: "Delete", symbol: "trash", danger: true) { SecretDialogs.openDeleteGroup(admin, g) }
        }
        .padding(.leading, Space.s6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("group-\(g.name)")
    }

    private func keys(_ press: KeyPress, _ model: SecretsModel) -> KeyPress.Result {
        let list = model.items.filter { SecretWords.matches($0, query: query, runner: runner) }
        let at = list.firstIndex { $0.name == cursor } ?? 0
        guard list.indices.contains(at) else { return .ignored }
        let step: Int? =
            switch press.key {
            case .upArrow, .leftArrow: -1
            case .downArrow, .rightArrow: 1
            default: nil
            }
        if let step {
            let i = at + step
            if list.indices.contains(i) { withAnimation(.smooth(duration: 0.25)) { cursor = list[i].name } }
            return .handled
        }
        let s = list[at]
        switch press.key {
        case .return:
            SecretDialogs.openLease(admin, s)
            return .handled
        case .delete, .deleteForward:
            SecretDialogs.openDelete(admin, s)
            return .handled
        default:
            switch press.characters.lowercased() {
            case "l": SecretDialogs.openLease(admin, s)
            case "e": SecretDialogs.openReplace(admin, s)
            default: return .ignored
            }
            return .handled
        }
    }
}

/// Whether the Core keeps secrets at all, in words, with a tile to Feature switches.
private struct ModePanel: View {
    let admin: AdminModel
    let mode: Int

    var body: some View {
        let hue = mode == 0 ? GlassInk.orange : GlassInk.blue
        HStack(spacing: Space.s3) {
            IconTile(mode == 0 ? "lock.fill" : "testtube.2", hue: hue, size: 44, bounce: mode)
                .shadow(color: hue.opacity(0.45), radius: 12)
            VStack(alignment: .leading, spacing: 2) {
                Text(mode == 0 ? "Secrets are off" : mode == 1 ? "Test values only" : "Real values")
                    .coreFont(size: MacTextSize.headline, weight: .bold).foregroundStyle(GlassInk.ink(hue))
                Text(
                    mode == 0
                        ? "Nothing can be added or lent until you turn on Test keys."
                        : mode == 1
                            ? "Anything that looks like a real key is refused, to keep you safe while testing."
                            : "Your Core keeps real secrets."
                )
                .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.s3)
            AppActionTile(title: "Change", symbol: "switch.2", key: "", hue: GlassInk.slate) {
                admin.host.shell.settings.selected = "switches"
            }
            .help("Keys and secrets in Feature switches (secrets.mode = \(mode))")
        }
        .padding(Space.s3)
        .background(hue.opacity(0.1), in: coreShape(Radius.cardMac))
        .overlay { coreShape(Radius.cardMac).strokeBorder(hue.opacity(0.35), lineWidth: 1) }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("secrets-mode")
    }
}

/// How a runner receives a secret, in words.
enum Delivery {
    static let all = ["env", "file", "askpass"]
    static func look(_ d: String) -> (title: String, line: String, symbol: String, hue: Color) {
        let w = SecretWords.delivery(d)
        let hue: Color =
            switch d {
            case "env": GlassInk.blue
            case "file": GlassInk.green
            case "askpass": GlassInk.violet
            default: GlassInk.slate
            }
        return (w.title, w.line, w.symbol, hue)
    }
}

/// One secret as a row: its type icon, name and how an agent gets it, who uses it, when it changed, and its sealed size.
/// Actions fade in on hover or with the cursor, and are in the context menu too.
private struct SecretRow: View {
    let admin: AdminModel
    let model: SecretsModel
    let secret: SecretItem
    let selected: Bool
    let pick: () -> Void
    @State private var hovering = false

    var body: some View {
        let kind = SecretWords.Kind(wire: secret.kind)
        let names = secret.runnersUsing.map(model.runnerName)
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s3) {
                IconTile(kind.symbol, hue: GlassInk.orange, size: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(secret.name).coreFont(size: MacTextSize.headline, weight: .semibold)
                        .lineLimit(1).truncationMode(.middle)
                    Text(SecretWords.line(secret)).coreFont(size: MacTextSize.meta)
                        .foregroundStyle(GlassInk.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Used by").coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                    Text(SecretWords.usedBy(names)).lineLimit(1)
                }
                .frame(width: Space.s8 * 5, alignment: .leading)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(SecretWords.lastUsed(secret)).coreFont(size: MacTextSize.meta).foregroundStyle(
                        GlassInk.secondary)
                    Text(SecretWords.sealed(secret)).lineLimit(1).coreFont(size: MacTextSize.meta, weight: .medium)
                        .padding(.horizontal, Space.s2).padding(.vertical, 1)
                        .background(GlassInk.wellHover, in: coreShape(5))
                }
                .frame(width: Space.s8 * 5, alignment: .trailing)
                HStack(spacing: Space.s1) {
                    AppActionTile(title: "", symbol: "arrow.triangle.2.circlepath", key: "", hue: GlassInk.slate) {
                        SecretDialogs.openReplace(admin, secret)
                    }
                    .help("New value (E)").accessibilityLabel("Replace the value of \(secret.name)")
                    AppActionTile(title: "", symbol: "server.rack", key: "", hue: GlassInk.orange) {
                        SecretDialogs.openLease(admin, secret)
                    }
                    .help("Let a runner use it (L)").accessibilityLabel("Let a runner use \(secret.name)")
                    AppActionTile(title: "", symbol: "trash", key: "", hue: GlassInk.red) {
                        SecretDialogs.openDelete(admin, secret)
                    }
                    .help("Delete \(secret.name) (⌫)").accessibilityLabel("Delete \(secret.name)")
                }
                .opacity(selected || hovering ? 1 : 0)
            }
            if let lease = model.leases.first(where: { $0.secret == secret.name }) { LeaseLine(lease: lease) }
            if let e = model.rowError[secret.name] { IssueLine(code: nil, text: e) }
        }
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
        .background(
            selected ? GlassInk.orange.opacity(0.12) : hovering ? GlassInk.wellHover : GlassInk.well,
            in: coreShape(Radius.cardMac)
        )
        .overlay {
            coreShape(Radius.cardMac).strokeBorder(
                selected ? GlassInk.orange.opacity(0.55) : GlassInk.wellEdge, lineWidth: selected ? 1.5 : 1)
        }
        .contentShape(coreShape(Radius.cardMac))
        .onTapGesture(perform: pick)
        .onHover { hovering = $0 }
        .animation(.smooth(duration: 0.2), value: hovering)
        .animation(.smooth(duration: 0.3), value: selected)
        .help("Key \(secret.keyID) · stored by \(secret.owner)")
        .contextMenu {
            Button("Let a runner use it…") { SecretDialogs.openLease(admin, secret) }
            Button("New value…") { SecretDialogs.openReplace(admin, secret) }
            Button("Delete…") { SecretDialogs.openDelete(admin, secret) }
            Button("Copy name") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(secret.name, forType: .string)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("secret-\(secret.name)")
        .coreActivates(pick)
    }
}

/// A loan from this Mac: to which runner, and the time left as a shrinking bar and a countdown.
private struct LeaseLine: View {
    let lease: LeaseItem
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let total = max(lease.expiresAt.timeIntervalSince(lease.grantedAt), 1)
            let left = max(lease.expiresAt.timeIntervalSince(ctx.date), 0)
            let hue = left > 0 ? GlassInk.green : GlassInk.slate
            VStack(alignment: .leading, spacing: Space.s1) {
                HStack {
                    Label("Allowed on \(lease.runner)", systemImage: "arrow.up.forward.circle.fill")
                        .coreFont(size: MacTextSize.meta, weight: .semibold).foregroundStyle(GlassInk.ink(hue))
                    Spacer()
                    Text(left > 0 ? Countdown.text(Int(left.rounded(.up))) : "Returned")
                        .coreFont(size: MacTextSize.body, weight: .bold, design: .rounded).monospacedDigit()
                        .foregroundStyle(GlassInk.ink(hue)).contentTransition(.numericText(countsDown: true))
                }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        coreShape(3).fill(GlassInk.track.opacity(0.6))
                        coreShape(3).fill(hue).frame(width: g.size.width * left / total)
                            .shadow(color: hue.opacity(0.6), radius: 5)
                    }
                }
                .frame(height: 5)
                .animation(.linear(duration: 1), value: left)
            }
            .padding(Space.s2)
            .background(hue.opacity(0.1), in: coreShape(Radius.control))
            .help(lease.lease)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "Allowed on \(lease.runner), \(left > 0 ? "\(Int(left.rounded(.up))) seconds left" : "returned")")
        }
    }
}

extension SecretsModel {
    func runnerName(_ id: String) -> String { runners.first { $0.id == id }?.name ?? id }
}

/// A small text action in a group's bar.
private struct AccGroupLink: View {
    let title: String
    let symbol: String
    var danger = false
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol).coreFont(size: MacTextSize.meta, weight: .medium)
        }
        .buttonStyle(.plain).focusable(false)
        .foregroundStyle(danger ? GlassInk.redInk : GlassInk.blue).opacity(enabled ? 1 : 0.4)
    }
}
