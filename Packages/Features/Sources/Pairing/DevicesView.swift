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
    @Environment(\.coreAccent) private var paneAccent
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
        HStack(alignment: .center, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("Devices").coreFont(size: MacTextSize.title, weight: .semibold).accessibilityAddTraits(.isHeader)
                Text("Phones and Macs that can reach your Core.").foregroundStyle(palette.text2)
            }
            Spacer(minLength: Space.s3)
            AppActionTile(
                title: "Add device (advanced)…", symbol: "slider.horizontal.3", key: "⌥⌘N",
                hue: GlassInk.accent(paneAccent)
            ) {
                app.openAddDevice()
            }
            .keyboardShortcut("n", modifiers: [.command, .option]).disabled(app.service == nil)
            AppActionTile(
                title: "Add device", symbol: "plus", key: "⌘N", hue: GlassInk.accent(paneAccent), prominent: true
            ) {
                app.openAddWizard()
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(app.service == nil)
        }
        if app.service == nil {
            NotConnectedNote(what: "Devices")
        } else {
            LoadNote(state: model.load) { Task { await model.reload() } }
            if let only = model.onlyAdmin {
                OnlyAdminWarning(app: app, device: only, next: model.nextAdmin(besides: only))
            }
            if model.load == .ready || !model.items.isEmpty {
                DeviceTable(app: app, model: model)
                Text("Removing a device signs it out at once. You can pair it again later.")
                    .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A device page's header, shown in the Settings title bar beside the back tile (N11).
private struct DeviceHeader: View {
    @Environment(\.coreAccent) private var paneAccent
    let app: AppModel
    let device: DeviceInfo
    @State private var shown = false

    private var hue: Color {
        device.revoked
            ? GlassInk.red : device.kind == "runner" ? GlassInk.accent(paneAccent) : GlassInk.accent(paneAccent)
    }

    var body: some View {
        HStack(spacing: Space.s4) {
            IconTile(DeviceWords.symbol(device.kind, device.platform), hue: hue, size: 56, bounce: shown)
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
    @Environment(\.coreAccent) private var paneAccent
    let app: AppModel
    let device: DeviceInfo
    /// The device that could become the second admin; nil when none can.
    let next: DeviceInfo?

    var body: some View {
        CoreNotice(
            symbol: "shield", title: "Only one device can approve things",
            text: "Make a second device an admin so you are never locked out.", tone: .warn
        ) {
            if let next {
                AppActionTile(
                    title: "Make \(next.name) an admin", symbol: "shield", key: "", hue: GlassInk.accent(paneAccent)
                ) {
                    Task { _ = await app.devices.setScopes(next, DeviceRole.withAdmin(next.scopes)) }
                }
            } else {
                AppActionTile(title: "Add an admin device", symbol: "plus", key: "", hue: GlassInk.accent(paneAccent)) {
                    app.openAddDevice(admin: true)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("only-admin")
    }
}

/// The devices as one-line rows: picture, name and kind, what it may do in a sentence, when it was seen, Remove.
private struct DeviceTable: View {
    let app: AppModel
    @Bindable var model: DevicesModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            if model.shown.isEmpty {
                Text("Nothing of that kind.").foregroundStyle(GlassInk.secondary).padding(Space.s3)
            }
            ForEach(model.shown) { d in
                DeviceRow(app: app, device: d) { model.detailID = d.id }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("device-table")
    }
}

private struct DeviceRow: View {
    @Environment(\.coreAccent) private var paneAccent
    let app: AppModel
    let device: DeviceInfo
    let open: () -> Void
    @Environment(\.corePalette) private var palette
    @State private var hovering = false

    var body: some View {
        let me = app.devices.isMe(device)
        let role = DeviceRole(scopes: device.scopes)
        HStack(spacing: Space.s3) {
            Button(action: open) {
                HStack(spacing: Space.s3) {
                    IconTile(
                        DeviceWords.symbol(device.kind, device.platform),
                        hue: device.revoked ? GlassInk.red : GlassInk.accent(paneAccent),
                        size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(device.name).coreFont(size: MacTextSize.body, weight: .semibold).lineLimit(1)
                        Text(
                            "\(DeviceWords.platform(device.platform)) · \(me ? "this device" : DeviceWords.kind(device.kind))"
                        )
                        .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2).lineLimit(1)
                    }
                    .frame(width: 200, alignment: .leading)
                    Label {
                        Text("\(role.title). \(role.line)").lineLimit(2)
                    } icon: {
                        Image(systemName: role.symbol)
                    }
                    .coreFont(size: MacTextSize.body).foregroundStyle(palette.text2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if device.revoked {
                        StateBadge("Revoked", tone: .fail, symbol: "xmark")
                    } else if !device.cutOff {
                        LastSeenLine(lastUsed: device.lastUsed).frame(width: 130, alignment: .leading)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open \(device.name)")
            if !device.revoked {
                Button("Remove") { remove() }
                    .buttonStyle(CoreButtonStyle(.quietDanger, size: .small))
                    .help("Sign \(device.name) out at once")
            }
        }
        .padding(.horizontal, Space.s4).padding(.vertical, Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .coreWell(active: hovering)
        .opacity(device.revoked ? 0.6 : 1)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .contain)
    }

    private func remove() {
        app.devices.dialogError = nil
        app.stepUpNotice = nil
        let device = device
        app.shell.present(
            ShellDialog(id: "revoke", onClose: { app.stepUpNotice = nil }) { RevokeDialog(app: app, device: device) })
    }
}

/// What a device may do, in one sentence (mockup 12): Admin, Member or Viewer, from the scopes it holds.
struct DeviceRole: Equatable {
    let title: String
    let line: String
    let symbol: String

    init(scopes: [String]) {
        if scopes.contains("admin") {
            self = DeviceRole(
                title: "Admin", line: "Can approve things, use your accounts and manage devices", symbol: "shield")
        } else if scopes.contains(where: { ["approve", "terminal", "agent", "runner"].contains($0) }) {
            self = DeviceRole(title: "Member", line: Self.memberLine(scopes), symbol: "person")
        } else {
            self = DeviceRole(title: "Viewer", line: "Can only look. It can't change anything", symbol: "eye")
        }
    }

    private init(title: String, line: String, symbol: String) {
        self.title = title
        self.line = line
        self.symbol = symbol
    }

    private static func memberLine(_ scopes: [String]) -> String {
        var does: [String] = []
        if scopes.contains("approve") { does.append("approve AI actions") }
        if scopes.contains("agent") { does.append("use your accounts") }
        if scopes.contains("terminal") { does.append("open terminals") }
        if scopes.contains("runner") { does.append("run work") }
        let first = does.joined(separator: ", ")
        return "Can " + (first.isEmpty ? "chat and see projects" : first)
    }

    /// The scopes with `admin` added, in the order the app lists them.
    static func withAdmin(_ scopes: [String]) -> [String] {
        scopes.contains("admin") ? scopes : scopes + ["admin"]
    }
}

/// The five scopes as small icon tiles, lit when held: access at a glance instead of "all five".
struct ScopeIcons: View {
    @Environment(\.coreAccent) private var paneAccent
    let scopes: [String]
    var body: some View {
        HStack(spacing: Space.s1 + 2) {
            ForEach(ScopeText.all, id: \.self) { s in
                let on = scopes.contains(s)
                IconTile(ScopeText.symbol(s), hue: on ? ScopeText.hue(s) : GlassInk.slate.opacity(0.35), size: 24)
                    .opacity(on ? 1 : 0.5)
                    .help(on ? "\(s.capitalized): \(ScopeText.text(s))" : "No \(s)")
            }
            if scopes.contains("runner") {
                IconTile(ScopeText.symbol("runner"), hue: GlassInk.accent(paneAccent), size: 24)
            }
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
    var body: some View { CoreChip(text) }
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
    @Environment(\.coreAccent) private var paneAccent
    let app: AppModel
    let device: DeviceInfo
    @Environment(\.corePalette) private var palette
    @State private var shown = false

    var body: some View {
        let me = app.devices.isMe(device)
        VStack(alignment: .leading, spacing: Space.s4) {
            GlassSection(
                "Device", sub: "Who it is, as it told the Core.", symbol: "info.circle",
                hue: GlassInk.accent(paneAccent), index: 1
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
                hue: GlassInk.accent(paneAccent), index: 2
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
                    hue: GlassInk.accent(paneAccent), index: 3
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
                    symbol: "lock.shield", hue: GlassInk.accent(paneAccent), index: 3
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
