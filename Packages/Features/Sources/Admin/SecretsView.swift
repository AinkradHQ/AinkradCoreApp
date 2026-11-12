import CoreUI
import Shell
import SwiftUI

/// Settings, Security, Secrets (N24, ui-fixes secrets.html): a line with the count and the two actions, the test-values
/// notice, search and the runner filter, then one section per group with one flat row per secret. Values go in and never
/// come back. Arrows move the cursor row; ↩ lets a runner use it, E gives it a new value, ⌫ deletes it, ⌘N adds one.
struct SecretsSection: View {
    let admin: AdminModel
    @State private var cursor: String?
    @State private var query = ""
    @State private var runner = ""
    @State private var closed: Set<String> = []
    @FocusState private var focus: Bool
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        let model = admin.secrets!
        VStack(alignment: .leading, spacing: Space.s4) {
            header(model)
            if admin.isConnected && model.isOff {
                CoreStateCard(
                    symbol: "lock", title: "Secrets are off", line: "Turn on test values to add one.",
                    primary: CoreAction("Open Feature switches") { admin.host.shell.settings.selected = "switches" }
                )
                .frame(maxWidth: .infinity).padding(.top, Space.s8)
                .accessibilityIdentifier("secrets-mode")
            } else {
                AdminScreen(
                    admin: admin, what: "Secrets", intro: "", state: model.state,
                    empty: ("No secrets yet", "Add a secret, then let a runner use it.", "key"),
                    emptyAction: ("New secret…", { SecretDialogs.openNew(admin) }),
                    retry: { Task { await model.reload() } }
                ) { list(model) }
            }
        }
        .task {
            await model.reload()
            focus = true
        }
        .accessibilityIdentifier("secrets")
    }

    // MARK: header

    private func header(_ model: SecretsModel) -> some View {
        HStack(spacing: Space.s2) {
            Text(SecretWords.header(count: model.items.count)).coreFont(size: MacTextSize.meta)
                .foregroundStyle(palette.text2)
            Spacer(minLength: Space.s3)
            Button {
                SecretDialogs.openGroup(admin, nil)
            } label: {
                Label("New group", systemImage: "folder")
            }
            .buttonStyle(CoreButtonStyle(.secondary, size: .small))
            .help("Keep related secrets together and give them to runners in one step")
            .disabled(model.isOff)
            Button {
                SecretDialogs.openNew(admin)
            } label: {
                Label("New secret", systemImage: "plus")
            }
            .buttonStyle(CoreButtonStyle(.prominent, size: .small))
            .keyboardShortcut("n", modifiers: .command).environment(\.coreKeycap, "⌘N")
            .help("Add a secret (⌘N)")
            .disabled(model.isOff)
        }
    }

    // MARK: the list

    private func list(_ model: SecretsModel) -> some View {
        let shown = model.items.filter { SecretWords.matches($0, query: query, runner: runner.isEmpty ? nil : runner) }
        return VStack(alignment: .leading, spacing: Space.s3) {
            if model.mode == 1 {
                CoreNotice(
                    symbol: "testtube.2", title: "Test values only",
                    text: "Anything that looks like a real key is refused."
                ) {
                    Button("Change…") { admin.host.shell.settings.selected = "switches" }
                        .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                        .help("Keys and secrets in Feature switches")
                }
                .accessibilityIdentifier("secrets-mode")
            }
            AdminNoticeBanner(notice: admin.host.elevationNotice)
            HStack(spacing: Space.s2) {
                CoreTextField("", placeholder: "Search secrets", text: $query).frame(maxWidth: Space.s8 * 9)
                CoreSelect(
                    nil, selection: $runner,
                    options: [CoreSelectOption("", "All runners")]
                        + model.runners.map { CoreSelectOption($0.id, $0.name, symbol: "server.rack") }
                )
                .frame(width: Space.s8 * 5)
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 0) {
                SecretColumns()
                if shown.isEmpty {
                    Text("No secret matches.").foregroundStyle(palette.text2).padding(Space.s3)
                }
                ForEach(
                    SecretSections.sections(shown, groups: model.groups, narrowed: !query.isEmpty || !runner.isEmpty)
                ) { section in
                    sectionView(section, model)
                }
            }
            SecretKeyHints().padding(.top, Space.s2)
        }
        .focusable().focused($focus).focusEffectDisabled()
        .onKeyPress(phases: .down) { keys($0, model) }
        .onChange(of: model.items.map(\.name), initial: true) { _, names in
            if !names.contains(cursor ?? "") { cursor = names.first }
        }
    }

    private func sectionView(_ section: SecretSectionItem, _ model: SecretsModel) -> some View {
        let open = !closed.contains(section.id)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.s2) {
                Button {
                    withAnimation(reduce ? nil : Motion.out(Motion.ui)) {
                        if open { closed.insert(section.id) } else { closed.remove(section.id) }
                    }
                } label: {
                    HStack(spacing: Space.s2) {
                        Image(systemName: "chevron.down").coreFont(size: MacTextSize.meta, weight: .semibold)
                            .rotationEffect(.degrees(open ? 0 : -90)).foregroundStyle(palette.text2)
                            .frame(width: Space.s4)
                        Image(systemName: section.group == nil ? "lock" : "folder").foregroundStyle(palette.primary)
                        Text(section.title).coreFont(size: MacTextSize.headline, weight: .semibold)
                        CountBadge(section.items.count, tone: .quiet, showsZero: true, label: "secrets")
                        if let g = section.group, !g.runners.isEmpty {
                            Text("Runners: " + g.runners.map(model.runnerName).joined(separator: ", "))
                                .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2).lineLimit(1)
                        }
                    }
                    .frame(minHeight: MacSize.controlMd)
                    .padding(.horizontal, Space.s1)
                    .contentShape(Rectangle())
                }
                .buttonStyle(CoreQuietPressStyle(radius: Radius.chip, scale: 0.99, hoverFill: true)).focusable(false)
                .padding(.horizontal, -Space.s1)  // grid: ok the fill bleeds 4 pt; the chevron stays on the rows' edge
                .accessibilityLabel("\(section.title), \(section.items.count) secrets")
                .accessibilityValue(open ? "Expanded" : "Collapsed")
                .help(section.group?.description ?? "")
                Spacer(minLength: Space.s2)
                if let g = section.group { GroupMenu(admin: admin, group: g) }
            }
            .padding(.horizontal, Space.s3).frame(minHeight: Space.s8 + Space.s3)
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(section.group.map { "group-\($0.name)" } ?? "group-none")
    }

    private func keys(_ press: KeyPress, _ model: SecretsModel) -> KeyPress.Result {
        let list = model.items.filter { SecretWords.matches($0, query: query, runner: runner.isEmpty ? nil : runner) }
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
            if list.indices.contains(i) { cursor = list[i].name }
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

/// The widths of the list's columns (mockup: name, 190 used by, 150 last used, 96 sealed size), on the 4 pt grid.
enum SecretColumn {
    static let tile: CGFloat = Space.s8 - Space.s1
    static let used: CGFloat = Space.s8 * 6
    static let last: CGFloat = Space.s8 * 5 - Space.s2
    static let size: CGFloat = Space.s8 * 3
}

/// The quiet column names above the rows.
private struct SecretColumns: View {
    @Environment(\.corePalette) private var palette
    var body: some View {
        HStack(spacing: Space.s3) {
            Text("Name").padding(.leading, SecretColumn.tile + Space.s3).frame(maxWidth: .infinity, alignment: .leading)
            Text("Used by").frame(width: SecretColumn.used, alignment: .leading)
            Text("Last used").frame(width: SecretColumn.last, alignment: .leading)
            Text("Sealed size").frame(width: SecretColumn.size, alignment: .trailing)
        }
        .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
        .padding(.horizontal, Space.s3).padding(.bottom, Space.s2)
        .accessibilityHidden(true)
    }
}

/// A group's actions behind one "…" on its header: edit, let a runner use all of it, delete.
private struct GroupMenu: View {
    let admin: AdminModel
    let group: SecretGroupItem
    @State private var open = false
    @State private var hovering = false
    @Environment(\.corePalette) private var palette

    var body: some View {
        CoreDropdown(
            items: [
                CoreDropdownItem("Edit group…", symbol: "pencil") { SecretDialogs.openGroup(admin, group) },
                CoreDropdownItem(
                    "Let a runner use all…", symbol: "server.rack",
                    enabled: !group.members.isEmpty && !group.runners.isEmpty
                ) { SecretDialogs.openGroupLease(admin, group) },
                CoreDropdownItem("Delete group…", symbol: "trash", destructive: true) {
                    SecretDialogs.openDeleteGroup(admin, group)
                },
            ], isPresented: $open
        ) {
            Image(systemName: "ellipsis").coreFont(size: MacTextSize.body, weight: .semibold)
                .foregroundStyle(palette.text2)
                .frame(width: MacSize.controlMd, height: MacSize.controlSm)
                .coreWell(radius: Radius.chip, active: hovering || open)
                .contentShape(coreShape(Radius.chip))
                .onHover { hovering = $0 }
                .animation(Motion.out(Motion.hover), value: hovering)
        }
        .help("Actions for \(group.name)")
        .accessibilityLabel("Actions for \(group.name)")
    }
}

/// One secret as a flat row: its type tile, name and line, who uses it (or the loan and its time left), when it was last
/// used and its sealed size. The selected row is lit and shows its three actions in place of the last two columns; the
/// context menu has them too.
private struct SecretRow: View {
    let admin: AdminModel
    let model: SecretsModel
    let secret: SecretItem
    let selected: Bool
    let pick: () -> Void
    @State private var hovering = false
    @Environment(\.corePalette) private var palette

    var body: some View {
        let kind = SecretWords.Kind(wire: secret.kind)
        let names = secret.runnersUsing.map(model.runnerName)
        let shape = coreShape(Radius.row)
        VStack(alignment: .leading, spacing: Space.s1) {
            HStack(spacing: Space.s3) {
                IconTile(kind.symbol, hue: names.isEmpty ? GlassInk.slate : GlassInk.blue, size: SecretColumn.tile)
                VStack(alignment: .leading, spacing: 0) {
                    Text(secret.name).coreFont(size: MacTextSize.body, weight: .medium)
                        .lineLimit(1).truncationMode(.middle)
                    Text(SecretWords.line(secret)).coreFont(size: MacTextSize.meta)
                        .foregroundStyle(palette.text2).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Group {
                    if let lease = model.leases.first(where: { $0.secret == secret.name }) {
                        LeaseCell(lease: lease, runner: model.runnerName(lease.runner))
                    } else {
                        Text(SecretWords.usedBy(names)).lineLimit(1).help(SecretWords.usedBy(names))
                    }
                }
                .frame(width: SecretColumn.used, alignment: .leading)
                HStack(spacing: Space.s3) {
                    Text(SecretWords.lastUsedShort(secret)).frame(width: SecretColumn.last, alignment: .leading)
                        .help(SecretWords.lastUsed(secret))
                    Text(SecretWords.size(secret.size)).coreFont(size: MacTextSize.meta).monospacedDigit()
                        .foregroundStyle(palette.text2).frame(width: SecretColumn.size, alignment: .trailing)
                }
                .opacity(selected ? 0 : 1)
            }
            // The worded actions float over the row's trailing end (secrets.html `.acts`), so they never widen the row
            // and push Used by out of its column.
            .overlay(alignment: .trailing) {
                if selected {
                    actions.padding(Space.s1)
                        .background(palette.panelStrong, in: coreShape(Radius.chip + Space.s1))
                        .overlay { coreShape(Radius.chip + Space.s1).strokeBorder(palette.edge, lineWidth: 1) }
                        .transition(.opacity)
                }
            }
            if let e = model.rowError[secret.name] {
                IssueLine(code: nil, text: e).padding(.leading, SecretColumn.tile + Space.s3)
            }
        }
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
        .frame(minHeight: Space.s8 + Space.s4)
        .background(selected ? palette.uDimHover : hovering ? palette.rowHover : .clear, in: shape)
        .overlay { if selected { shape.strokeBorder(palette.navActiveEdge, lineWidth: 1) } }
        .contentShape(shape)
        .onTapGesture(perform: pick)
        .onHover { hovering = $0 }
        .animation(Motion.out(Motion.hover), value: hovering)
        .animation(Motion.out(Motion.hover), value: selected)
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

    /// The selected row's actions, worded, each with its key.
    private var actions: some View {
        HStack(spacing: Space.s1) {
            Button {
                SecretDialogs.openLease(admin, secret)
            } label: {
                Label("Let a runner use it", systemImage: "server.rack")
            }
            .environment(\.coreKeycap, "↩").help("Let a runner use \(secret.name) for a short time (↩)")
            .buttonStyle(CoreButtonStyle(.secondary, size: .small))
            Button("New value") { SecretDialogs.openReplace(admin, secret) }
                .environment(\.coreKeycap, "E").help("Replace the value of \(secret.name) (E)")
                .buttonStyle(CoreButtonStyle(.secondary, size: .small))
            Button("Delete") { SecretDialogs.openDelete(admin, secret) }
                .environment(\.coreKeycap, "⌫").help("Delete \(secret.name) (⌫)")
                .buttonStyle(CoreButtonStyle(.quietDanger, size: .small))
        }
        .fixedSize()
    }
}

/// A loan from this Mac in the Used by column: to which runner and the time left, in words and as a meter.
private struct LeaseCell: View {
    let lease: LeaseItem
    let runner: String
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let total = max(lease.expiresAt.timeIntervalSince(lease.grantedAt), 1)
            let left = max(lease.expiresAt.timeIntervalSince(ctx.date), 0)
            let words = SecretWords.lent(to: runner, secondsLeft: Int(left.rounded(.up)))
            VStack(alignment: .leading, spacing: Space.s1) {
                Text(words).lineLimit(1).monospacedDigit().contentTransition(.numericText(countsDown: true))
                CoreMeter(left / total, low: left > 0 && left < 60, label: words)
            }
            .help(lease.lease)
            .accessibilityElement(children: .combine)
        }
    }
}

/// The keys of the list, at its foot.
private struct SecretKeyHints: View {
    @Environment(\.corePalette) private var palette
    var body: some View {
        HStack(spacing: Space.s4) {
            hint(["↑", "↓"], "move")
            hint(["↩"], "let a runner use it")
            hint(["E"], "new value")
            hint(["⌫"], "delete")
            hint(["⌘N"], "new secret")
        }
        .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
        .padding(.horizontal, Space.s3)
        .accessibilityElement(children: .combine)
    }

    private func hint(_ keys: [String], _ what: String) -> some View {
        HStack(spacing: Space.s1) {
            ForEach(keys, id: \.self) { CoreKeycap($0) }
            Text(what)
        }
    }
}

extension SecretsModel {
    func runnerName(_ id: String) -> String { runners.first { $0.id == id }?.name ?? id }
}

/// How a runner receives a secret.
enum Delivery {
    static let all = ["env", "file", "askpass"]
}
