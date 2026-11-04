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

private struct DeviceTable: View {
    let app: AppModel
    @Bindable var model: DevicesModel
    @Environment(\.corePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                CoreSegmented(
                    "Filter devices",
                    segments: DeviceFilter.allCases.map { CoreSegment($0, $0.rawValue) }, selection: $model.filter)
                Spacer(minLength: Space.s3)
                Text("\(model.shown.count) of \(model.items.count)").foregroundStyle(palette.text2)
                    .font(.system(size: MacTextSize.body).monospacedDigit())
            }
            if model.shown.isEmpty {
                Text("Nothing of that kind.").foregroundStyle(palette.text2).padding(Space.s3)
            }
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: Space.s8 * 7), spacing: Space.s3, alignment: .top)],
                spacing: Space.s3
            ) {
                ForEach(model.shown) { d in DeviceCard(app: app, device: d) { model.detailID = d.id } }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("device-table")
    }
}

/// One device as a card (the prototype's grid): icon tile, name with the This Mac tag, platform, kind and key storage, access,
/// last seen. No outline at rest; the focus ring shows only on the card the keyboard is on.
private struct DeviceCard: View {
    let app: AppModel
    let device: DeviceInfo
    let open: () -> Void
    @Environment(\.corePalette) private var palette
    @FocusState private var focused: Bool
    @State private var hovering = false

    var body: some View {
        let me = app.devices.isMe(device)
        Button(action: open) {
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(alignment: .top, spacing: Space.s2) {
                    Image(systemName: DeviceWords.symbol(device.kind, device.platform))
                        .font(.system(size: MacTextSize.title)).foregroundStyle(palette.primary)
                        .frame(width: MacSize.controlLg, height: MacSize.controlLg)
                        .background(palette.uDim, in: coreShape(Radius.control)).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: Space.s1) {
                            Text(device.name).font(.system(size: MacTextSize.headline, weight: .semibold)).lineLimit(1)
                            if me { StateBadge("This Mac", tone: .done, symbol: "desktopcomputer") }
                        }
                        Text(DeviceWords.platform(device.platform)).font(.system(size: MacTextSize.meta))
                            .foregroundStyle(palette.text2).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: Space.s2) {
                    Chip(text: device.kind)
                    KeyStorageLabel(storage: device.keyStorage)
                    if device.revoked { StateBadge("Revoked", tone: .fail, symbol: "xmark") }
                }
                AccessChips(scopes: device.scopes)
                LastSeenLine(lastUsed: device.lastUsed)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.s3)
            .background(hovering ? palette.rowHover : palette.glassCard, in: coreShape(Radius.row))
            .opacity(device.revoked ? 0.6 : 1)
            .contentShape(coreShape(Radius.row))
        }
        .buttonStyle(.plain)
        .focused($focused).focusEffectDisabled()
        .coreFocusRing(focused, radius: Radius.row, palette: palette)
        .onHover { hovering = $0 }
        .animation(Motion.out(Motion.hover), value: hovering)
        .accessibilityLabel(
            "\(device.name), \(me ? "This Mac, " : "")\(DeviceWords.kind(device.kind)), \(device.keyStorage ?? "storage not reported"), \(device.scopes.joined(separator: ", ")), last seen \(DeviceWords.seen(device.lastUsed))"
        )
        .accessibilityHint("Opens this device's page")
    }
}

/// Where the key lives: a shield for the Secure Enclave, an amber warning for software. What the device reported, not verified.
struct KeyStorageLabel: View {
    let storage: String?
    @Environment(\.corePalette) private var palette
    var body: some View {
        let software = storage == "software"
        Label {
            Text(storage.map { $0 == "secure_enclave" ? "Secure Enclave" : $0 } ?? "not reported")
        } icon: {
            Image(systemName: software ? "exclamationmark.triangle" : "checkmark.shield")
        }
        .font(.system(size: MacTextSize.meta))
        .foregroundStyle(software ? palette.tone(.warn).ink : palette.text2)
        .lineLimit(1)
    }
}

/// "Active now" with a quiet pulse while the device was seen in the last minute, else "Last seen 3 days ago".
struct LastSeenLine: View {
    let lastUsed: Date?
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var on = false
    var body: some View {
        let fresh = lastUsed.map { Date().timeIntervalSince($0) < 60 } ?? false
        HStack(spacing: Space.s1) {
            if fresh {
                coreShape(2).fill(palette.tone(.done).ink).frame(width: 7, height: 7)
                    .opacity(on && !reduce ? 0.35 : 1)
                    .animation(reduce ? nil : .easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: on)
                    .onAppear { on = true }
                    .accessibilityHidden(true)
            }
            Text(fresh ? "Active now" : "Last seen \(DeviceWords.seen(lastUsed))")
        }
        .font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
    }
}

/// A small rounded-rect tag: a kind, a scope.
struct Chip: View {
    let text: String
    var tint: Tone?
    @Environment(\.corePalette) private var palette
    var body: some View {
        Text(text).font(.system(size: MacTextSize.meta, design: .monospaced)).lineLimit(1)
            .foregroundStyle(tint.map { palette.tone($0).ink } ?? palette.text)
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

/// Rename in place: a field with Save and Cancel. A Touch ID that does not go through leaves the edit where it is.
private struct InlineRename: View {
    let app: AppModel
    let device: DeviceInfo
    @State private var name: String

    init(app: AppModel, device: DeviceInfo) {
        self.app = app
        self.device = device
        _name = State(initialValue: device.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            CoreTextField("Name", placeholder: "1 to 64 characters", text: $name, autofocus: true) { go() }
            StepUpBanner(app: app)
            ErrorLine(text: app.devices.dialogError)
            HStack(spacing: Space.s2) {
                Button("Save") { go() }.buttonStyle(CoreButtonStyle(.prominent, busy: app.devices.busy))
                    .disabled(name.isEmpty || name == device.name).keyboardShortcut(.defaultAction)
                Button("Cancel") { stop() }.buttonStyle(.coreSecondary).keyboardShortcut(.cancelAction)
            }
        }
        .onAppear {
            app.devices.dialogError = nil
            app.stepUpNotice = nil
        }
    }

    private func go() {
        Task { if await app.devices.rename(device, to: name) { stop() } }
    }

    private func stop() {
        app.stepUpNotice = nil
        app.devices.renaming = false
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
                if app.devices.renaming {
                    InlineRename(app: app, device: device)
                } else {
                    HStack {
                        FactRow(key: "Name", value: device.name)
                        if !device.revoked {
                            Button("Rename…") { app.devices.renaming = true }.buttonStyle(.coreSecondary)
                        }
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
