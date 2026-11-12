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
                CoreBusyBar().frame(maxWidth: Space.s8 * 5)
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
        @Bindable var model = model
        AboutBlock(app: app)
        HStack(alignment: .center, spacing: Space.s3) {
            Text(
                app.service == nil
                    ? "Every device that can reach a Core."
                    : "\(model.active.count) can reach this Core. Revoking signs a device out at once."
            )
            .foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Space.s3)
            if app.service != nil, !model.items.isEmpty {
                CoreSegmented(
                    "Show",
                    segments: DeviceFilter.allCases.map { f in
                        CoreSegment(f, "\(f.rawValue) \(model.items.filter { f.matches($0.kind) }.count)")
                    }, selection: $model.filter
                )
                .fixedSize()
            }
            AppActionTile(
                title: "Add device (advanced)…", symbol: "slider.horizontal.3", key: "⌥⌘N", hue: GlassInk.blue
            ) {
                app.openAddDevice()
            }
            .keyboardShortcut("n", modifiers: [.command, .option]).disabled(app.service == nil)
            AppActionTile(title: "Add device", symbol: "plus", key: "⌘N", hue: GlassInk.blue, prominent: true) {
                app.openAddWizard()
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(app.service == nil)
        }
        if app.service == nil {
            NotConnectedNote(what: "Devices")
        } else {
            LoadNote(state: model.load) { Task { await model.reload() } }
            if let only = model.onlyAdmin { OnlyAdminWarning(app: app, device: only) }
            if model.load == .ready || !model.items.isEmpty {
                DeviceTable(app: app, model: model)
                Text("Where a key is kept is what each device said when it paired. Your Core can't check it.")
                    .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A device page's header, shown in the Settings title bar beside the back tile (N11).
private struct DeviceHeader: View {
    let app: AppModel
    let device: DeviceInfo
    @State private var shown = false

    private var hue: Color {
        device.revoked ? GlassInk.red : device.kind == "runner" ? GlassInk.blue : GlassInk.blue
    }

    var body: some View {
        HStack(spacing: Space.s4) {
            IconTile(DeviceWords.symbol(device.kind, device.platform), hue: hue, size: 56, bounce: shown)
                .shadow(color: hue.opacity(0.45), radius: 12)
            VStack(alignment: .leading, spacing: Space.s1 / 2) {
                HStack(spacing: Space.s2) {
                    Text(device.name).coreFont(size: MacTextSize.large + 6, weight: .bold)
                        .accessibilityAddTraits(.isHeader)
                    if app.devices.isMe(device) { StateBadge("This Mac", tone: .done, symbol: "desktopcomputer") }
                    if device.revoked { StateBadge("Revoked", tone: .fail, symbol: "xmark") }
                }
                Text("\(DeviceWords.kind(device.kind)) · \(DeviceWords.platform(device.platform))")
                    .foregroundStyle(GlassInk.secondary)
                if !device.cutOff { LastSeenLine(lastUsed: device.lastUsed) }
            }
        }
        .onAppear { shown = true }
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
                Text("Only one admin device").coreFont(size: MacTextSize.headline, weight: .semibold)
                Text(
                    "\(device.name) is the only device that can manage this Core. If you lose it, you would be locked out. Add a second admin device, such as your iPhone."
                )
                .foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.s2)
            AppActionTile(title: "Add an admin device", symbol: "plus", key: "", hue: GlassInk.blue) {
                app.openAddDevice(admin: true)
            }
        }
        .coreFont(size: MacTextSize.body)
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
    @State private var cursor: String?
    @FocusState private var focus: Bool

    private func keys(_ press: KeyPress) -> KeyPress.Result {
        let ids = model.shown.map(\.id)
        guard !ids.isEmpty else { return .ignored }
        let i = ids.firstIndex { $0 == cursor } ?? 0
        let step: Int? =
            switch press.key {
            case .rightArrow, .downArrow: 1
            case .leftArrow, .upArrow: -1
            default: nil
            }
        if let step {
            withAnimation(.smooth(duration: 0.25)) { cursor = ids[min(max(i + step, 0), ids.count - 1)] }
            return .handled
        }
        if press.key == .return, let c = cursor {
            model.detailID = c
            return .handled
        }
        return .ignored
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            if model.shown.isEmpty {
                Text("Nothing of that kind.").foregroundStyle(palette.text2).padding(Space.s3)
            }
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: Space.s8 * 9), spacing: Space.s4, alignment: .top)],
                spacing: Space.s3
            ) {
                ForEach(Array(model.shown.enumerated()), id: \.element.id) { i, d in
                    DeviceCard(app: app, device: d, index: i, selected: cursor == d.id) { model.detailID = d.id }
                }
            }
        }
        // ↑ ↓ ← → move the cursor tile, Return opens it.
        .focusable().focused($focus).focusEffectDisabled()
        .onKeyPress(phases: .down) { press in keys(press) }
        .onAppear {
            cursor = cursor ?? model.shown.first?.id
            focus = true
        }
        .onChange(of: model.shown.map(\.id)) { _, ids in if !ids.contains(cursor ?? "") { cursor = ids.first } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("device-table")
    }
}

/// One device as a tile: a large device picture with a live mark for this Mac, the name, platform, where its keys live,
/// its access as five scope icons, and when it was last seen. Lifts on hover; tiles rise in one after another.
private struct DeviceCard: View {
    let app: AppModel
    let device: DeviceInfo
    var index = 0
    var selected = false
    let open: () -> Void
    @Environment(\.corePalette) private var palette
    @State private var hovering = false
    @State private var shown = false

    private var hue: Color {
        device.revoked ? GlassInk.red : device.kind == "runner" ? GlassInk.blue : GlassInk.blue
    }

    var body: some View {
        let me = app.devices.isMe(device)
        Button(action: open) {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(alignment: .top, spacing: Space.s3) {
                    IconTile(DeviceWords.symbol(device.kind, device.platform), hue: hue, size: 52).coreEnterBounce(
                        hovering
                    )
                    .overlay(alignment: .bottomTrailing) {
                        if me {
                            StatusDot(color: GlassInk.green, live: true).offset(x: 4, y: 4)
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: Space.s1) {
                            Text(device.name).coreFont(size: MacTextSize.title, weight: .semibold).lineLimit(1)
                            if me { StateBadge("This Mac", tone: .done, symbol: "desktopcomputer") }
                            if device.revoked { StateBadge("Revoked", tone: .fail, symbol: "xmark") }
                        }
                        Text("\(DeviceWords.kind(device.kind)) · \(DeviceWords.platform(device.platform))")
                            .coreFont(size: MacTextSize.body).foregroundStyle(GlassInk.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                KeyStorageLabel(storage: device.keyStorage)
                ScopeIcons(scopes: device.scopes)
                if !device.cutOff { LastSeenLine(lastUsed: device.lastUsed) }
            }
            .foregroundStyle(GlassInk.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.s4)
            .background(
                selected ? hue.opacity(0.12) : hovering ? GlassInk.wellHover : GlassInk.well,
                in: coreShape(Radius.cardMac)
            )
            .overlay {
                coreShape(Radius.cardMac).strokeBorder(
                    selected ? hue.opacity(0.6) : GlassInk.wellEdge, lineWidth: selected ? 1.5 : 1)
            }
            .shadow(color: hue.opacity(selected ? 0.3 : 0), radius: 12)
            .opacity(device.revoked ? 0.6 : 1)
            .contentShape(coreShape(Radius.cardMac))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .coreScaleEffect(hovering ? 1.02 : 1)
        .shadow(color: GlassInk.shade(hovering ? 0.25 : 0), radius: 16, y: 8)
        .onHover { hovering = $0 }
        .animation(.smooth(duration: 0.3), value: hovering)
        .animation(.smooth(duration: 0.3), value: selected)
        .coreRise(shown, index)
        .onAppear { shown = true }
        .accessibilityLabel(
            "\(device.name), \(me ? "This Mac, " : "")\(DeviceWords.kind(device.kind)), \(device.keyStorage ?? "storage not reported"), \(device.scopes.joined(separator: ", ")), last seen \(DeviceWords.seen(device.lastUsed))"
        )
        .accessibilityHint("Opens this device's page")
    }
}

/// The five scopes as small icon tiles, lit when held: access at a glance instead of "all five".
struct ScopeIcons: View {
    let scopes: [String]
    var body: some View {
        HStack(spacing: Space.s1 + 2) {
            ForEach(ScopeText.all, id: \.self) { s in
                let on = scopes.contains(s)
                IconTile(ScopeText.symbol(s), hue: on ? ScopeText.hue(s) : GlassInk.slate.opacity(0.35), size: 24)
                    .opacity(on ? 1 : 0.5)
                    .help(on ? "\(s.capitalized): \(ScopeText.text(s))" : "No \(s)")
            }
            if scopes.contains("runner") { IconTile(ScopeText.symbol("runner"), hue: GlassInk.blue, size: 24) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(scopes.joined(separator: ", "))
    }
}

/// Where the key lives: a shield for the Secure Enclave, an amber warning for software. What the device reported, not verified.
struct KeyStorageLabel: View {
    let storage: String?
    @Environment(\.corePalette) private var palette
    var body: some View {
        let software = storage == "software"
        Label {
            Text(
                storage == "secure_enclave"
                    ? "Key locked in the device's chip"
                    : software ? "Key kept in a file" : "Didn't say where its key is")
        } icon: {
            Image(systemName: software ? "exclamationmark.triangle" : "checkmark.shield")
        }
        .coreFont(size: MacTextSize.meta)
        .foregroundStyle(software ? palette.tone(.warn).ink : palette.text2)
        .lineLimit(1)
        .help(
            software
                ? "A key in a file can be copied if the device is taken. A chip (Secure Enclave) can't give its key away."
                : storage ?? "not reported")
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
        .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
    }
}

/// A small rounded-rect tag: a kind, a scope.
struct Chip: View {
    let text: String
    var tint: Tone?
    @Environment(\.corePalette) private var palette
    var body: some View {
        Text(text).coreFont(size: MacTextSize.meta, design: .monospaced).lineLimit(1)
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
                    .disabled(name.isEmpty || name == device.name).coreShortcut(.primary)
                Button("Cancel") { stop() }.buttonStyle(.coreSecondary).coreShortcut(.cancel)
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
    @State private var shown = false

    var body: some View {
        let me = app.devices.isMe(device)
        VStack(alignment: .leading, spacing: Space.s4) {
            GlassSection(
                "Device", sub: "Who it is, as it told the Core.", symbol: "info.circle", hue: GlassInk.blue, index: 1
            ) {
                if !device.revoked && !app.devices.renaming {
                    SectionAction("Rename", symbol: "pencil") { app.devices.renaming = true }
                }
            } content: {
                if app.devices.renaming {
                    InlineRename(app: app, device: device)
                } else {
                    InfoRow("textformat", "Name", device.name)
                }
                InfoRow("square.stack.3d.up", "Kind", DeviceWords.kind(device.kind))
                InfoRow("laptopcomputer", "Platform", DeviceWords.platform(device.platform))
                InfoRow("number", "Device ID", device.id, mono: true)
                InfoRow("calendar", "Paired", device.createdAt.formatted(date: .abbreviated, time: .shortened))
                InfoRow("waveform.path.ecg", "Status", device.status.capitalized)
            }
            GlassSection(
                "Keys", sub: "Made on the device. The Core only holds the public halves.", symbol: "key.horizontal",
                hue: GlassInk.blue, index: 2
            ) {
                HStack(spacing: Space.s3) {
                    KeyFact(
                        symbol: device.keyStorage == "software" ? "exclamationmark.triangle" : "cpu",
                        title: DeviceWords.storage(device.keyStorage),
                        detail: device.keyStorage == "software" ? "Kept in a file" : "Locked in the device's chip",
                        hue: device.keyStorage == "software" ? GlassInk.amber : GlassInk.green)
                    KeyFact(
                        symbol: device.stepup == true ? "touchid" : "touchid",
                        title: device.stepup.map { $0 ? "Can use Touch ID" : "No Touch ID key" } ?? "Didn't say",
                        detail: device.stepup == true ? "Asks for the person" : "Can never unlock admin actions",
                        hue: device.stepup == true ? GlassInk.green : GlassInk.slate)
                }
                if let fp = device.fingerprint { FingerprintView(fingerprint: fp) }
            }
            if device.kind == "runner" {
                // N18: a runner does the work the Core sends; it does not ask for anything, so scopes do not describe it.
                GlassSection(
                    "Access", sub: "A runner does work; it does not ask for it.", symbol: "server.rack",
                    hue: GlassInk.blue, index: 3
                ) {
                    SectionAction("Open runner page", symbol: "arrow.right") {
                        app.shell.launcher.entry("runners")?.run()
                        app.terminals?.openRunners(device.id)
                    }
                } content: {
                    Text(
                        "Connection: runner. It can only receive work from this Core. What it offers, what runs on it and who may use it are on its runner page."
                    )
                    .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
                }
            } else {
                GlassSection(
                    "Access", sub: "What it may do. You can only narrow it; to give more, pair it again.",
                    symbol: "lock.shield", hue: GlassInk.blue, index: 3
                ) {
                    if !device.revoked {
                        SectionAction("Edit access", symbol: "slider.horizontal.3") {
                            present("scopes", ScopesDialog(app: app, device: device))
                        }
                    }
                } content: {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: Space.s2)], spacing: Space.s2) {
                        ForEach(ScopeText.all, id: \.self) { s in
                            ScopeTile(
                                symbol: ScopeText.symbol(s), name: s, detail: ScopeText.text(s), hue: ScopeText.hue(s),
                                on: device.scopes.contains(s))
                        }
                    }
                }
            }
            if !device.revoked {
                GlassSection(
                    "Revoke", sub: "Signs it out at once. It has to pair again to come back.", symbol: "xmark.shield",
                    hue: GlassInk.red, index: 4
                ) {
                    SectionAction("Revoke device", symbol: "xmark.shield", danger: true) {
                        present("revoke", RevokeDialog(app: app, device: device))
                    }
                } content: {
                    Text(
                        me
                            ? "Revoking this Mac signs it out at once and returns it to Connect to a Core. It must be paired again."
                            : "Revoking signs \(device.name) out at once and closes its open connections. It must be paired again."
                    )
                    .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .foregroundStyle(GlassInk.primary)
        .onAppear {
            shown = true
            // The way back sits in the Settings title bar, beside the Devices icon.
            // The device's own header replaces the section's: icon, name, badges, kind and last seen.
            app.shell.settings.back = SettingsBack(
                title: "Devices",
                header: { [app, id = device.id] in
                    AnyView(DeviceHeader(app: app, device: app.devices.items.first { $0.id == id } ?? device))
                }
            ) { app.devices.detailID = nil }
        }
        .onDisappear { app.shell.settings.back = nil }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("device-detail")
    }

    private func present(_ id: String, _ view: some View) {
        app.devices.dialogError = nil
        app.stepUpNotice = nil
        app.shell.present(ShellDialog(id: id, onClose: { app.stepUpNotice = nil }) { view })
    }
}
