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
            HStack(spacing: Space.s2) {
                Spin()
                Text("Loading…").foregroundStyle(palette.text2)
            }
            .accessibilityElement(children: .combine)
        case .failed(let m):
            ConnectionBanner(.error(m), retry: retry)
        default: EmptyView()
        }
    }
}

struct DevicesSection: View {
    let app: AppModel
    @Environment(\.corePalette) private var palette

    var body: some View {
        let model = app.devices!
        VStack(alignment: .leading, spacing: Space.s4) {
            HStack {
                Text("Every device that can reach this Core. Changes here need Touch ID.")
                    .foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Space.s3)
                Button("Add device") { app.openAddDevice() }.buttonStyle(.coreProminent)
                    .disabled(app.service == nil)
            }
            if app.service == nil {
                NotConnectedNote(what: "Devices")
            } else {
                LoadNote(state: model.load) { Task { await model.reload() } }
                ForEach(model.active) { d in DeviceRow(app: app, device: d) }
                if model.load == .ready && model.active.isEmpty {
                    Text("No devices yet.").foregroundStyle(palette.text2)
                }
                if !model.revoked.isEmpty {
                    Text("Revoked").font(.system(size: MacTextSize.body, weight: .semibold))
                        .foregroundStyle(palette.text2).padding(.top, Space.s2).accessibilityAddTraits(.isHeader)
                    ForEach(model.revoked) { d in DeviceRow(app: app, device: d) }
                }
            }
        }
        .frame(maxWidth: Space.s8 * 20, alignment: .leading)
        .task { await model.reload() }
    }
}

private struct DeviceRow: View {
    let app: AppModel
    let device: DeviceInfo
    @Environment(\.corePalette) private var palette

    var body: some View {
        let me = app.devices.isMe(device)
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: DeviceWords.symbol(device.kind, device.platform)).font(.system(size: MacTextSize.title))
                .foregroundStyle(palette.primary).frame(width: MacSize.controlMd).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.s1) {
                HStack(spacing: Space.s2) {
                    Text(device.name).font(.system(size: MacTextSize.headline, weight: .semibold))
                    if me { StateBadge("This Mac", tone: .done, symbol: "desktopcomputer") }
                    if device.revoked { StateBadge("Revoked", tone: .fail, symbol: "xmark") }
                }
                Text(
                    [
                        DeviceWords.kind(device.kind), DeviceWords.platform(device.platform),
                        DeviceWords.storage(device.keyStorage),
                    ]
                    .joined(separator: " · ")
                )
                .font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
                Text("May: \(device.scopes.joined(separator: ", "))")
                    .font(.system(size: MacTextSize.meta, design: .monospaced)).foregroundStyle(palette.text2)
                Text("Last seen: \(DeviceWords.seen(device.lastUsed))")
                    .font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
            }
            Spacer(minLength: Space.s2)
            if !device.revoked {
                HStack(spacing: Space.s1) {
                    CoreIconButton(symbol: "pencil", label: "Rename \(device.name)") { rename() }
                    CoreIconButton(symbol: "slider.horizontal.3", label: "Change what \(device.name) may do") {
                        scopes()
                    }
                    CoreIconButton(symbol: "trash", label: "Revoke \(device.name)") { revoke() }
                }
            }
        }
        .padding(Space.s3)
        .background(palette.glassCard, in: coreShape(Radius.row))
        .opacity(device.revoked ? 0.6 : 1)
        .accessibilityElement(children: .contain)
    }

    private func present(_ id: String, _ view: some View) {
        app.devices.dialogError = nil
        app.shell.present(ShellDialog(id: id) { view })
    }

    private func rename() { present("rename", RenameDialog(app: app, device: device)) }
    private func scopes() { present("scopes", ScopesDialog(app: app, device: device)) }
    private func revoke() { present("revoke", RevokeDialog(app: app, device: device)) }
}

// MARK: dialogs

private struct DialogButtons: View {
    let app: AppModel
    let confirm: String
    var destructive = false
    var busy: Bool
    var enabled = true
    let run: () -> Void

    var body: some View {
        HStack(spacing: Space.s2) {
            Spacer(minLength: 0)
            Button("Cancel") { app.shell.closeDialog() }.buttonStyle(.coreSecondary).keyboardShortcut(.cancelAction)
            Button(confirm, action: run).buttonStyle(CoreButtonStyle(destructive ? .secondary : .prominent, busy: busy))
                .keyboardShortcut(destructive ? nil : .defaultAction).disabled(!enabled)
        }
    }
}

private struct ErrorLine: View {
    let text: String?
    @Environment(\.corePalette) private var palette
    var body: some View {
        if let text {
            Label(text, systemImage: "exclamationmark.triangle").foregroundStyle(palette.tone(.fail).ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct RenameDialog: View {
    let app: AppModel
    let device: DeviceInfo
    @State private var name: String

    init(app: AppModel, device: DeviceInfo) {
        self.app = app
        self.device = device
        _name = State(initialValue: device.name)
    }

    var body: some View {
        DialogCard(title: "Rename device", width: Space.s8 * 13) {
            FieldBox(label: "Name", placeholder: "1 to 64 characters", text: $name, autofocus: true) { go() }
            ErrorLine(text: app.devices.dialogError)
            DialogButtons(app: app, confirm: "Rename", busy: app.devices.busy, enabled: !name.isEmpty, run: go)
        }
    }

    private func go() {
        Task { if await app.devices.rename(device, to: name) { app.shell.closeDialog() } }
    }
}

struct ScopesDialog: View {
    let app: AppModel
    let device: DeviceInfo
    @State private var on: Set<String>

    init(app: AppModel, device: DeviceInfo) {
        self.app = app
        self.device = device
        _on = State(initialValue: Set(device.scopes))
    }

    var body: some View {
        DialogCard(title: "What \(device.name) may do", width: Space.s8 * 15) {
            VStack(alignment: .leading, spacing: Space.s3) {
                Text("You can take scopes away here. To give more, pair the device again.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if device.kind == "runner" {
                    Text("A runner holds exactly runner. Revoke it to remove its access.")
                } else {
                    ForEach(ScopeText.all, id: \.self) { s in
                        ScopeToggle(
                            scope: s,
                            on: Binding(
                                get: { on.contains(s) }, set: { if $0 { on.insert(s) } else { on.remove(s) } }),
                            locked: device.scopes.contains(s) ? nil : "It does not hold this. Pair again to add it.")
                    }
                }
                ErrorLine(text: app.devices.dialogError)
                DialogButtons(
                    app: app, confirm: "Save", busy: app.devices.busy,
                    enabled: device.kind != "runner" && on != Set(device.scopes)
                ) {
                    Task {
                        if await app.devices.setScopes(device, ScopeText.all.filter(on.contains)) {
                            app.shell.closeDialog()
                        }
                    }
                }
            }
            .font(.system(size: MacTextSize.body))
        }
    }
}

struct RevokeDialog: View {
    let app: AppModel
    let device: DeviceInfo

    var body: some View {
        let me = app.devices.isMe(device)
        DialogCard(title: me ? "Revoke this Mac?" : "Revoke \(device.name)?", width: Space.s8 * 13) {
            VStack(alignment: .leading, spacing: Space.s3) {
                Text(
                    me
                        ? "This Mac loses access at once and goes back to Connect to a Core. It must be paired again to return. Revoking cannot be undone."
                        : "\(device.name) loses access at once and its open connections close. It must be paired again to return. Revoking cannot be undone."
                )
                .fixedSize(horizontal: false, vertical: true)
                ErrorLine(text: app.devices.dialogError)
                DialogButtons(app: app, confirm: "Revoke", destructive: true, busy: app.devices.busy) {
                    Task { if await app.devices.revoke(device) { app.shell.closeDialog() } }
                }
            }
            .font(.system(size: MacTextSize.body))
        }
    }
}
