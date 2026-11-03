import CoreUI
import Shell
import SwiftUI

/// What an unconnected Mac shows instead of data: never a made-up list.
struct NotConnectedNote: View {
    let what: String
    @Environment(\.corePalette) private var palette
    var body: some View {
        Label("\(what) come from your Core. This Mac is not connected to one right now.", systemImage: "wifi.slash")
            .foregroundStyle(palette.text2)
    }
}

struct LoadNote: View {
    let state: LoadState
    let retry: () -> Void
    @Environment(\.corePalette) private var palette
    var body: some View {
        switch state {
        case .loading:
            VStack(alignment: .leading, spacing: Space.s1) {
                IndBar().frame(maxWidth: Space.s8 * 5)
                Text("Loading…").foregroundStyle(palette.text2)
            }
            .accessibilityElement(children: .combine)
        case .failed(let m):
            ConnectionBanner(.error(m), retry: retry)
        default: EmptyView()
        }
    }
}

/// Settings, Devices: the list as a table, or one device's page.
struct DevicesSection: View {
    let app: AppModel
    @Environment(\.corePalette) private var palette

    var body: some View {
        let model = app.devices!
        VStack(alignment: .leading, spacing: Space.s4) {
            if let d = model.detail {
                DeviceDetail(app: app, device: d)
            } else {
                list(model)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { await model.reload() }
    }

    @ViewBuilder private func list(_ model: DevicesModel) -> some View {
        HStack(alignment: .top) {
            Text(
                app.service == nil
                    ? "Every device that can reach a Core."
                    : "\(model.active.count) can reach this Core. Revoking signs a device out at once."
            )
            .foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Space.s3)
            Button("Add device…") { app.openAddDevice() }.buttonStyle(.coreProminent).disabled(app.service == nil)
        }
        if app.service == nil {
            NotConnectedNote(what: "Devices")
        } else {
            LoadNote(state: model.load) { Task { await model.reload() } }
            if let only = model.onlyAdmin { OnlyAdminWarning(app: app, device: only) }
            if model.load == .ready || !model.items.isEmpty {
                DeviceTable(app: app, model: model)
                Text(
                    "Key storage is what each device reported when it paired. The Core records it as a claim and can't verify it."
                )
                .font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct OnlyAdminWarning: View {
    let app: AppModel
    let device: DeviceInfo
    @Environment(\.corePalette) private var palette

    var body: some View {
        let t = palette.tone(.warn)
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(t.ink).frame(width: Space.s4)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.s1 / 2) {
                Text("Only one admin device").font(.system(size: MacTextSize.headline, weight: .semibold))
                Text(
                    "\(device.name) is the only device that can manage this Core. If you lose it, getting back in needs SSH to the host. Add a second admin device, such as your iPhone."
                )
                .foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.s2)
            Button("Add device…") { app.openAddDevice() }.buttonStyle(.coreSecondary)
        }
        .font(.system(size: MacTextSize.body))
        .padding(Space.s3)
        .background(palette.glassCard, in: coreShape(Radius.cardMac))
        .background(t.fill, in: coreShape(Radius.cardMac))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("only-admin")
    }
}

/// Column widths: the table is laid out on these so header and rows line up.
private enum Col {
    static let icon = MacSize.controlLg
    static let kind = Space.s8 * 2
    static let storage = Space.s8 * 3
    static let access = Space.s8 * 4
    static let seen = Space.s8 * 2 + Space.s2
}

private struct DeviceTable: View {
    let app: AppModel
    @Bindable var model: DevicesModel
    @Environment(\.corePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                CoreSegmented(
                    "Filter devices",
                    segments: DeviceFilter.allCases.map { CoreSegment($0, $0.rawValue) }, selection: $model.filter)
                Spacer(minLength: Space.s3)
                Text("\(model.shown.count) of \(model.items.count)").foregroundStyle(palette.text2)
                    .font(.system(size: MacTextSize.body).monospacedDigit())
            }
            header
            if model.shown.isEmpty {
                Text("Nothing of that kind.").foregroundStyle(palette.text2).padding(Space.s3)
            }
            ForEach(model.shown) { d in
                Button {
                    model.detailID = d.id
                } label: {
                    row(d)
                }
                .buttonStyle(TableRowStyle())
                .accessibilityLabel(
                    "\(d.name), \(app.devices.isMe(d) ? "This Mac, " : "")\(DeviceWords.kind(d.kind)), \(d.keyStorage ?? "storage not reported"), \(d.scopes.joined(separator: ", ")), last seen \(DeviceWords.seen(d.lastUsed))"
                )
                .accessibilityHint("Opens this device's page")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("device-table")
    }

    private var header: some View {
        HStack(spacing: Space.s2) {
            Color.clear.frame(width: Col.icon, height: 1)
            Text("Name").frame(maxWidth: .infinity, alignment: .leading)
            Text("Kind").frame(width: Col.kind, alignment: .leading)
            Text("Key storage").frame(width: Col.storage, alignment: .leading)
            Text("Access").frame(width: Col.access, alignment: .leading)
            Text("Last seen").frame(width: Col.seen, alignment: .leading)
        }
        .font(.system(size: MacTextSize.meta, weight: .semibold)).foregroundStyle(palette.text2)
        .padding(.horizontal, Space.s3)
        .accessibilityHidden(true)
    }

    private func row(_ d: DeviceInfo) -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: DeviceWords.symbol(d.kind, d.platform)).font(.system(size: MacTextSize.title))
                .foregroundStyle(palette.primary).frame(width: Col.icon, height: Col.icon)
                .background(palette.uDim, in: coreShape(Radius.control)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: Space.s1) {
                    Text(d.name).font(.system(size: MacTextSize.headline, weight: .semibold)).lineLimit(1)
                    if app.devices.isMe(d) { StateBadge("This Mac", tone: .done, symbol: "desktopcomputer") }
                    if d.revoked { StateBadge("Revoked", tone: .fail, symbol: "xmark") }
                }
                Text(DeviceWords.platform(d.platform)).font(.system(size: MacTextSize.meta))
                    .foregroundStyle(palette.text2).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Chip(text: d.kind).frame(width: Col.kind, alignment: .leading)
            Text(d.keyStorage ?? "not reported")
                .font(.system(size: MacTextSize.meta, design: .monospaced))
                .foregroundStyle(d.keyStorage == "software" ? palette.tone(.warn).ink : palette.text)
                .frame(width: Col.storage, alignment: .leading).lineLimit(1)
            AccessChips(scopes: d.scopes).frame(width: Col.access, alignment: .leading)
            Text(DeviceWords.seen(d.lastUsed)).font(.system(size: MacTextSize.body))
                .frame(width: Col.seen, alignment: .leading).lineLimit(1)
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s2)
        .frame(minHeight: MacSize.controlLg + Space.s5)
        .opacity(d.revoked ? 0.6 : 1)
    }
}

/// A small rounded-rect tag: a kind, a scope.
struct Chip: View {
    let text: String
    @Environment(\.corePalette) private var palette
    var body: some View {
        Text(text).font(.system(size: MacTextSize.meta, design: .monospaced)).lineLimit(1)
            .padding(.horizontal, Space.s2).frame(minHeight: MacSize.chip)
            .background(palette.uDim, in: coreShape(Radius.chip))
    }
}

/// The scopes a device holds: all five as one word, else the first two and how many more.
struct AccessChips: View {
    let scopes: [String]
    var body: some View {
        let ordered = ScopeText.all.filter(scopes.contains) + scopes.filter { !ScopeText.all.contains($0) }
        HStack(spacing: Space.s1) {
            if ScopeText.all.allSatisfy(scopes.contains) {
                Chip(text: "all five")
            } else {
                ForEach(ordered.prefix(2), id: \.self) { Chip(text: $0) }
                if ordered.count > 2 { Chip(text: "+\(ordered.count - 2)") }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(scopes.joined(separator: ", "))
    }
}

private struct TableRowStyle: ButtonStyle {
    @Environment(\.corePalette) private var palette
    @Environment(\.isFocused) private var focused
    @State private var hovering = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                hovering || configuration.isPressed ? palette.rowHover : palette.glassCard, in: coreShape(Radius.row)
            )
            .coreFocusRing(focused, radius: Radius.row, palette: palette)
            .contentShape(coreShape(Radius.row))
            .onHover { hovering = $0 }
            .animation(Motion.out(Motion.hover), value: hovering)
            .focusEffectDisabled()
    }
}

/// One device's page: Device, Keys, Access, Revoke. Back returns to the list.
struct DeviceDetail: View {
    let app: AppModel
    let device: DeviceInfo
    @Environment(\.corePalette) private var palette

    var body: some View {
        let me = app.devices.isMe(device)
        VStack(alignment: .leading, spacing: Space.s4) {
            HStack(spacing: Space.s2) {
                Button {
                    app.devices.detailID = nil
                } label: {
                    Label("Devices", systemImage: "chevron.left")
                }
                .buttonStyle(.coreSecondary).keyboardShortcut(.leftArrow, modifiers: .command)
                .accessibilityLabel("Back to Devices")
                Spacer()
            }
            HStack(spacing: Space.s2) {
                Text(device.name).font(.system(size: MacTextSize.large, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                if me { StateBadge("This Mac", tone: .done, symbol: "desktopcomputer") }
                if device.revoked { StateBadge("Revoked", tone: .fail, symbol: "xmark") }
            }
            section("Device") {
                HStack {
                    FactRow(key: "Name", value: device.name)
                    if !device.revoked {
                        Button("Rename…") { present("rename", RenameDialog(app: app, device: device)) }
                            .buttonStyle(.coreSecondary)
                    }
                }
                FactRow(key: "Kind", value: device.kind, mono: true)
                FactRow(key: "Platform", value: DeviceWords.platform(device.platform))
                FactRow(key: "Device ID", value: device.id, mono: true)
                FactRow(key: "Paired", value: device.createdAt.formatted(date: .abbreviated, time: .shortened))
                FactRow(key: "Last seen", value: DeviceWords.seen(device.lastUsed))
                FactRow(key: "Status", value: device.status)
            }
            section("Keys") {
                FactRow(key: "Key storage", value: DeviceWords.storage(device.keyStorage))
                FactRow(
                    key: "Step-up key",
                    value: device.stepup.map {
                        $0 ? "Yes: it asks for the user" : "None: it can never unlock admin actions"
                    }
                        ?? "Not reported")
                if let fp = device.fingerprint { FactRow(key: "Fingerprint", value: fp, mono: true) }
            }
            section("Access") {
                Text(
                    device.scopes.isEmpty
                        ? "No scopes." : device.scopes.map { "\($0): \(ScopeText.text($0))" }.joined(separator: "\n")
                )
                .font(.system(size: MacTextSize.body)).fixedSize(horizontal: false, vertical: true)
                if !device.revoked {
                    Button("Change access…") { present("scopes", ScopesDialog(app: app, device: device)) }
                        .buttonStyle(.coreSecondary)
                }
            }
            if !device.revoked {
                section("Revoke") {
                    Text(
                        me
                            ? "Revoking this Mac signs it out at once and returns it to Connect to a Core. It must be paired again."
                            : "Revoking signs \(device.name) out at once and closes its open connections. It must be paired again."
                    )
                    .foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
                    Button("Revoke…") { present("revoke", RevokeDialog(app: app, device: device)) }
                        .buttonStyle(DangerButtonStyle())
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("device-detail")
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(title).font(.system(size: MacTextSize.body, weight: .semibold)).foregroundStyle(palette.text2)
                .accessibilityAddTraits(.isHeader)
            FactCard { content() }
        }
    }

    private func present(_ id: String, _ view: some View) {
        app.devices.dialogError = nil
        app.stepUpNotice = nil
        app.shell.present(ShellDialog(id: id, onClose: { app.stepUpNotice = nil }) { view })
    }
}
