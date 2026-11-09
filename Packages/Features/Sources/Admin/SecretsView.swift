import CoreUI
import Shell
import SwiftUI

/// Settings, Security, Secrets: what your Core keeps, in plain words. Values go in and never come back. One card is the
/// cursor (arrows); L lends it to a runner, E gives it a new value, ⌫ deletes it, ⌘N adds one.
struct SecretsSection: View {
    let admin: AdminModel
    @State private var cursor: String?
    @FocusState private var focus: Bool

    var body: some View {
        let model = admin.secrets!
        AdminScreen(
            admin: admin, what: "Secrets",
            intro:
                "Values go in and never come back: nobody can show or copy them, not even you. Runners borrow them for a short time.",
            state: model.state,
            empty: ("No secrets yet", "Add a test value, then lend it to a runner.", "key"),
            emptyAction: ("New secret…", { SecretDialogs.openNew(admin) }),
            retry: { Task { await model.reload() } }
        ) {
            VStack(alignment: .leading, spacing: Space.s4) {
                ModePanel(admin: admin, mode: model.mode)
                AdminNoticeBanner(notice: admin.host.elevationNotice)
                GlassSection(
                    "Your secrets", sub: "\(model.items.count) kept. Each asks for Touch ID to change.",
                    symbol: "key.fill", hue: GlassInk.orange, index: 1
                ) {
                    AppActionTile(title: "New secret", symbol: "plus", key: "⌘N", hue: GlassInk.orange, prominent: true)
                    {
                        SecretDialogs.openNew(admin)
                    }
                    .keyboardShortcut("n", modifiers: .command)
                } content: {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: Space.s3, alignment: .top), count: 3),
                        spacing: Space.s3
                    ) {
                        ForEach(model.items) { s in
                            SecretCard(admin: admin, model: model, secret: s, selected: cursor == s.name) {
                                cursor = s.name
                                focus = true
                            }
                        }
                    }
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

    private func keys(_ press: KeyPress, _ model: SecretsModel) -> KeyPress.Result {
        let list = model.items
        let at = list.firstIndex { $0.name == cursor } ?? 0
        guard list.indices.contains(at) else { return .ignored }
        let step: Int? =
            switch press.key {
            case .leftArrow: -1
            case .rightArrow: 1
            case .upArrow: -3
            case .downArrow: 3
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
                    .font(.system(size: MacTextSize.headline, weight: .bold)).foregroundStyle(GlassInk.ink(hue))
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
        switch d {
        case "env": ("Variable", "As an environment variable", "terminal.fill", GlassInk.blue)
        case "file": ("File", "As a file only it can read", "doc.fill", GlassInk.green)
        case "askpass": ("Prompt", "Answers git's password prompt", "key.horizontal.fill", GlassInk.violet)
        default: (d, d, "questionmark", GlassInk.slate)
        }
    }
}

private struct SecretCard: View {
    let admin: AdminModel
    let model: SecretsModel
    let secret: SecretItem
    let selected: Bool
    let pick: () -> Void
    @State private var hovering = false

    var body: some View {
        let look = Delivery.look(secret.delivery)
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: Space.s3) {
                IconTile("key.fill", hue: GlassInk.orange, size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(secret.name).font(.system(size: MacTextSize.headline, weight: .semibold))
                        .lineLimit(1).truncationMode(.middle)
                    Text(
                        secret.version == 1 ? "First value" : "Value \(secret.version), replaced \(secret.version - 1)×"
                    )
                    .font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary)
                }
                Spacer(minLength: 0)
            }
            SealedValue(size: secret.size, hue: GlassInk.orange)
            VStack(alignment: .leading, spacing: Space.s2) {
                fact(look.symbol, look.hue, look.line)
                if secret.runners.isEmpty {
                    fact("server.rack", GlassInk.slate, "No runner may borrow it yet")
                } else {
                    fact(
                        "server.rack", GlassInk.green,
                        "May borrow: \(secret.runners.map(model.runnerName).joined(separator: ", "))")
                }
            }
            if let lease = model.leases.first(where: { $0.secret == secret.name }) { LeaseLine(lease: lease) }
            if let e = model.rowError[secret.name] { IssueLine(code: nil, text: e) }
            HStack(spacing: Space.s2) {
                AppActionTile(title: "", symbol: "trash", key: selected ? "⌫" : "", hue: GlassInk.red) {
                    SecretDialogs.openDelete(admin, secret)
                }
                .help("Delete \(secret.name)")
                .accessibilityLabel("Delete \(secret.name)")
                Spacer(minLength: 0)
                AppActionTile(
                    title: "New value", symbol: "arrow.triangle.2.circlepath", key: selected ? "E" : "",
                    hue: GlassInk.slate
                ) {
                    SecretDialogs.openReplace(admin, secret)
                }
                .accessibilityLabel("Replace the value of \(secret.name)")
                AppActionTile(
                    title: "Lend", symbol: "arrow.up.forward", key: selected ? "L" : "", hue: GlassInk.orange,
                    prominent: selected
                ) {
                    SecretDialogs.openLease(admin, secret)
                }
                .accessibilityLabel("Lease \(secret.name)")
            }
            .opacity(selected || hovering ? 1 : 0.55)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            selected ? GlassInk.orange.opacity(0.12) : hovering ? GlassInk.wellHover : GlassInk.well,
            in: coreShape(Radius.cardMac)
        )
        .overlay {
            coreShape(Radius.cardMac).strokeBorder(
                selected ? GlassInk.orange.opacity(0.55) : GlassInk.wellEdge, lineWidth: selected ? 1.5 : 1)
        }
        .shadow(color: GlassInk.orange.opacity(selected ? 0.3 : 0), radius: 12)
        .contentShape(coreShape(Radius.cardMac))
        .onTapGesture(perform: pick)
        .onHover { hovering = $0 }
        .animation(.smooth(duration: 0.3), value: selected)
        .animation(.smooth(duration: 0.2), value: hovering)
        .help("Key \(secret.keyID) · stored by \(secret.owner)")
        .contextMenu {
            Button("Lend…") { SecretDialogs.openLease(admin, secret) }
            Button("New value…") { SecretDialogs.openReplace(admin, secret) }
            Button("Delete…") { SecretDialogs.openDelete(admin, secret) }
            Button("Copy name") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(secret.name, forType: .string)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("secret-\(secret.name)")
    }

    private func fact(_ symbol: String, _ hue: Color, _ text: String) -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(hue)
                .frame(width: 22, height: 22).background(hue.opacity(0.16), in: coreShape(6))
            Text(text).lineLimit(2)
        }
        .font(.system(size: MacTextSize.body))
    }
}

/// The value as a sealed strip: a lock, one block per four bytes (its length, never its content) and the size.
private struct SealedValue: View {
    let size: Int64
    let hue: Color

    var body: some View {
        let n = Int(min(max((size + 3) / 4, 1), 14))
        HStack(spacing: Space.s2) {
            Image(systemName: "lock.fill").foregroundStyle(hue)
            HStack(spacing: 2) {
                ForEach(0..<n, id: \.self) { _ in coreShape(2).fill(.white.opacity(0.35)).frame(width: 7, height: 12) }
            }
            Spacer(minLength: 0)
            Text("\(size) bytes · hidden").font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary)
        }
        .padding(.horizontal, Space.s3).frame(height: 34)
        .background(.black.opacity(0.22), in: coreShape(Radius.control))
        .overlay { coreShape(Radius.control).strokeBorder(GlassInk.wellEdge, lineWidth: 1) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Value, \(size) bytes, hidden")
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
                    Label("Lent to \(lease.runner)", systemImage: "arrow.up.forward.circle.fill")
                        .font(.system(size: MacTextSize.meta, weight: .semibold)).foregroundStyle(GlassInk.ink(hue))
                    Spacer()
                    Text(left > 0 ? Countdown.text(Int(left.rounded(.up))) : "Returned")
                        .font(.system(size: MacTextSize.body, weight: .bold, design: .rounded).monospacedDigit())
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
                "Lent to \(lease.runner), \(left > 0 ? "\(Int(left.rounded(.up))) seconds left" : "returned")")
        }
    }
}

extension SecretsModel {
    func runnerName(_ id: String) -> String { runners.first { $0.id == id }?.name ?? id }
}
