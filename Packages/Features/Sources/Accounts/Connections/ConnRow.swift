import CoreUI
import SwiftUI

/// One connection: logo, service and who, what AI may do, how much it reaches, when it was last used (only when the Core
/// says), the state, Change…, and More.
struct ConnRow: View {
    let model: ConnectionsModel
    let item: ConnItem
    /// Some connection has a last-used time: every row keeps the column, so the columns line up.
    var showUsed = false
    @State private var menuOpen = false
    @State private var moreHover = false
    @Environment(\.corePalette) private var palette

    private var kind: ConnKind? { model.kind(item.kind) }
    private var oauth: Bool { item.authMethod == "oauth" }

    /// The four of the mockup first, then the rest of what a connection can do, Disconnect last.
    private var menuItems: [CoreDropdownItem] {
        let noun = kind?.resource ?? "places"
        var out = [
            CoreDropdownItem("What AI may do…", symbol: "eye") { model.beginEdit(item, at: .allow) },
            CoreDropdownItem("Choose \(noun)…", symbol: "folder") { model.beginEdit(item, at: .choose) },
            CoreDropdownItem("Sign in again", symbol: "arrow.clockwise", enabled: oauth) { model.beginAgain(item) },
            CoreDropdownItem("Test connection", symbol: "checkmark.seal") {
                Task {
                    await model.test(item)
                    if let said = model.tested[item.id] { model.host.shell.showToast(said) }
                }
            },
            CoreDropdownItem("Rename…", symbol: "pencil") { ConnDialogs.openRename(model, item) },
            item.isDefault
                ? CoreDropdownItem("Clear default", symbol: "star.slash") { Task { await model.clearDefault(item) } }
                : CoreDropdownItem("Use by default", symbol: "star") { Task { await model.makeDefault(item) } },
        ]
        if !oauth {
            out.append(CoreDropdownItem("Replace token…", symbol: "key") { ConnDialogs.openReplace(model, item) })
        }
        if !model.host.shell.settings.hidden.contains("audit") {
            out.append(CoreDropdownItem("History", symbol: "clock.arrow.circlepath") { model.openHistory(item) })
        }
        out.append(
            CoreDropdownItem("Disconnect", symbol: "trash", destructive: true) { model.disconnectWithUndo(item) })
        return out
    }

    private func column(_ title: String, _ value: String, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value.isEmpty ? "" : title).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
            Text(value).coreFont(size: MacTextSize.body)
        }
        .lineLimit(1).frame(width: width, alignment: .leading)
    }

    var body: some View {
        let (label, tone, symbol) = ConnLook.chip(item)
        let on = model.cursor == item.id
        HStack(spacing: Space.s4) {
            ConnLogo(kind: item.kind, size: 40, lit: item.status == .connected)
            VStack(alignment: .leading, spacing: 0) {
                let service = kind?.name ?? item.name
                Text(item.label.isEmpty ? service : item.label).coreFont(size: MacTextSize.body, weight: .semibold)
                    .lineLimit(1)
                Text(item.label.isEmpty ? item.identity : "\(service) · \(item.identity)").coreFont(size: MacTextSize.meta)
                    .foregroundStyle(GlassInk.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            column("Access", ConnAccess.lead(kind, allowed: item.allowed), width: 140)
            column("Can see", ConnAccess.scope(kind, only: item.only, seen: item.seen), width: 132)
            if showUsed {
                column("Last used", item.lastUsed.map { ConnAccess.used($0) } ?? "", width: 96)
            }
            StateBadge(label, tone: tone, symbol: symbol).frame(width: 112, alignment: .leading)
                .help(item.reason ?? "")
            HStack(spacing: Space.s2) {
                if item.signInNeeded && oauth {
                    Button("Sign in") { model.beginAgain(item) }.buttonStyle(CoreButtonStyle(.secondary, size: .small))
                }
                Button("Change…") { model.beginEdit(item, at: .allow) }
                    .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                    .help("Change what your assistant may do on \(kind?.name ?? item.name)")
            }
            .frame(width: 148, alignment: .trailing)
            CoreDropdown(items: menuItems, isPresented: $menuOpen) {
                Image(systemName: "ellipsis").coreFont(size: MacTextSize.body, weight: .semibold)
                    .foregroundStyle(GlassInk.primary)
                    .frame(width: MacSize.controlMd, height: MacSize.controlSm)
                    .background(moreHover || menuOpen ? GlassInk.wellHover : Color.clear, in: coreShape(Radius.chip))
                    .contentShape(coreShape(Radius.chip))
                    .onHover { moreHover = $0 }
                    .animation(Motion.out(Motion.hover), value: moreHover)
            }
            .help("More")
            .accessibilityLabel("More actions for \(kind?.name ?? item.name)")
        }
        .padding(.horizontal, Space.s4).padding(.vertical, Space.s3)
        .frame(minHeight: 68)
        .background(GlassInk.well, in: coreShape(Radius.cardMac))
        .overlay { if on { coreShape(Radius.cardMac).fill(palette.navActive).allowsHitTesting(false) } }
        .contextMenu {
            ForEach(menuItems) { i in
                Button(i.title, role: i.destructive ? .destructive : nil) { i.run() }.disabled(!i.enabled)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(kind?.name ?? item.name), \(item.identity), \(label)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
