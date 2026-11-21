import CoreUI
import Shell
import SwiftUI
import Terminals

/// A phone, iPad or Mac that only signs in to the Core, as its page in Machines (mockup a-devices): what it may do, a few
/// details, rename and remove. A Mac can start doing work from here: this Mac with its switch, another Mac through Add
/// machine with its name filled in. Keys: esc back (Machines), ⌘⌫ remove, ⌘R rename.
struct SignInPage: View {
    let app: AppModel
    let id: String
    let back: () -> Void
    @Environment(\.corePalette) private var palette
    @Environment(\.coreAccent) private var paneAccent

    private var devices: DevicesModel { app.devices }
    private var device: DeviceInfo? { devices.items.first { $0.id == id } }

    var body: some View {
        if let d = device {
            content(d)
        } else {
            LoadNote(state: devices.load == .ready ? .failed("This machine is no longer listed.") : devices.load) {
                Task { await devices.reload() }
            }
        }
    }

    private func content(_ d: DeviceInfo) -> some View {
        let me = devices.isMe(d)
        let machine = AppModel.signIn(d, me: me)
        return VStack(alignment: .leading, spacing: Space.s6) {
            header(d, me: me, symbol: machine.symbol)
            if devices.renaming { InlineRename(app: app, device: d) }
            switch machine.promote(macRunnerAvailable: app.macRunner.isAvailable) {
            case .thisMacSwitch?: ThisMacWork(app: app)
            case .runWorkHere?: runWorkHere(d)
            case nil: EmptyView()
            }
            if me, let only = devices.onlyAdmin, only.id == d.id {
                OnlyAdminWarning(app: app, device: d, next: devices.nextAdmin(besides: d))
            }
            scopes(d)
            details(d)
            remove(d, me: me)
        }
        .foregroundStyle(GlassInk.primary)
        .onDisappear { devices.renaming = false }
        .accessibilityIdentifier("sign-in-page")
    }

    private func header(_ d: DeviceInfo, me: Bool, symbol: String) -> some View {
        HStack(alignment: .center, spacing: Space.s4) {
            IconTile(symbol, hue: GlassInk.accent(paneAccent), size: Space.s8 + Space.s6)
            VStack(alignment: .leading, spacing: Space.s1) {
                HStack(spacing: Space.s3) {
                    Text(me ? "This Mac" : d.name).coreFont(size: MacTextSize.large, weight: .bold).lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                    StateBadge("Signed in", tone: .done, symbol: "circle")
                }
                Text(line(d, me: me)).foregroundStyle(palette.text2).lineLimit(1)
            }
            Spacer(minLength: Space.s3)
            CoreDropdown(items: [
                CoreDropdownItem("Rename…", symbol: "pencil", note: "⌘R") { devices.renaming = true },
                CoreDropdownItem("Remove…", symbol: "trash", destructive: true, note: "⌘⌫") { confirmRemove(d) },
            ]) {
                Image(systemName: "ellipsis").frame(width: MacSize.controlMd, height: MacSize.controlMd)
                    .background(GlassInk.well, in: coreShape(Radius.control))
                    .accessibilityLabel("More for \(d.name)")
            }
            .help("Rename or remove \(d.name)")
            .background {
                // ⌘R renames from the page itself; the menu item shows the key.
                Button("") { devices.renaming = true }.keyboardShortcut("r", modifiers: .command)
                    .opacity(0).accessibilityHidden(true)
            }
        }
    }

    private func line(_ d: DeviceInfo, me: Bool) -> String {
        let seen = d.lastUsed.map { "last seen " + $0.formatted(.relative(presentation: .named)) } ?? "not seen yet"
        return me ? "Signs in here · \(d.name)" : "Signs in to your Core · \(seen)"
    }

    /// Another Mac: it does work once the runner runs on it. Add machine opens on a server or another Mac, with this name.
    private func runWorkHere(_ d: DeviceInfo) -> some View {
        HStack(spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Let \(d.name) do work").coreFont(size: MacTextSize.body, weight: .semibold)
                Text("AI sessions and terminals can run on it too. You finish it on that Mac.")
                    .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
            }
            Spacer(minLength: Space.s3)
            Button("Run work here →") { app.openAddMachine(.server(name: d.name)) }
                .buttonStyle(CoreButtonStyle(.secondary))
                .keyboardShortcut(.defaultAction).environment(\.coreKeycap, "⏎")
                .help("Open Add machine for \(d.name) (⏎)")
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading).coreWell()
    }

    /// What it may do, one switch per scope. Switching one off narrows it at once with Undo; adding one is pairing again.
    private func scopes(_ d: DeviceInfo) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("What it may do").coreFont(size: MacTextSize.body, weight: .semibold).foregroundStyle(palette.text2)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: Space.s3) {
                ForEach(ScopeText.all, id: \.self) { s in
                    let held = d.scopes.contains(s)
                    HStack(spacing: Space.s3) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(ScopeText.text(s)).coreFont(size: MacTextSize.body, weight: .medium)
                            Text(held ? Self.scopeNote(s) : "To give this, add it again").coreFont(
                                size: MacTextSize.meta
                            )
                            .foregroundStyle(palette.text2)
                        }
                        Spacer(minLength: Space.s3)
                        CoreSwitch(
                            "",
                            isOn: Binding(
                                get: { held },
                                set: { on in
                                    guard !on else { return }
                                    Task { _ = await devices.setScopes(d, d.scopes.filter { $0 != s }) }
                                })
                        )
                        .accessibilityLabel(ScopeText.text(s))
                        .disabled(!held || devices.busy || d.scopes.count == 1)
                        .help(held ? "Take this away from \(d.name). Undo brings it back" : "Add it again to give this")
                    }
                }
                ErrorLine(text: devices.dialogError)
            }
            .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading).coreWell()
        }
    }

    static func scopeNote(_ s: String) -> String {
        switch s {
        case "read": "Read only"
        case "approve": "Best kept on one phone you carry"
        case "terminal": "Can change files where a terminal runs"
        case "agent": "Uses your AI accounts"
        case "admin": "Can change everything, including other machines"
        default: s
        }
    }

    private func details(_ d: DeviceInfo) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("Details").coreFont(size: MacTextSize.body, weight: .semibold).foregroundStyle(palette.text2)
                .accessibilityAddTraits(.isHeader)
            Grid(alignment: .leading, horizontalSpacing: Space.s8 * 3, verticalSpacing: Space.s2) {
                fact("Added", d.createdAt.formatted(date: .abbreviated, time: .omitted))
                fact("System", DeviceWords.platform(d.platform))
                fact("Last seen", d.lastUsed.map { $0.formatted(.relative(presentation: .named)) } ?? "Not seen yet")
                fact("Key", DeviceWords.keyNote(d.keyStorage))
                if let fp = d.fingerprint { fact("Fingerprint", fp, mono: true) }
            }
        }
    }

    private func fact(_ k: String, _ v: String, mono: Bool = false) -> some View {
        GridRow {
            Text(k).foregroundStyle(palette.text2)
            Text(v).coreFont(size: mono ? MacTextSize.meta : MacTextSize.body, design: mono ? .monospaced : .default)
                .lineLimit(1).truncationMode(.middle).textSelection(.enabled).help(v)
        }
    }

    private func remove(_ d: DeviceInfo, me: Bool) -> some View {
        HStack(spacing: Space.s3) {
            Button("Remove \(me ? "this Mac" : d.name)…") { confirmRemove(d) }
                .buttonStyle(CoreButtonStyle(.quietDanger))
                .keyboardShortcut(.delete, modifiers: .command).environment(\.coreKeycap, "⌘⌫")
                .help("Sign \(d.name) out of your Core (⌘⌫)")
            Text(
                me
                    ? "This Mac is signed out and goes back to Connect."
                    : "It is signed out at once. You can add it again later."
            )
            .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
        }
    }

    private func confirmRemove(_ d: DeviceInfo) {
        devices.dialogError = nil
        app.stepUpNotice = nil
        app.shell.present(
            ShellDialog(id: "revoke", onClose: { [app] in app.stepUpNotice = nil }) {
                RevokeDialog(app: app, device: d)
            })
    }
}

extension AppModel {
    /// A device as Machines shows it among the ones that only sign in. A passkey is a browser: platform "web".
    static func signIn(_ d: DeviceInfo, me: Bool) -> SignInMachine {
        SignInMachine(
            id: d.id, name: d.name, platform: d.kind == "passkey" ? "web" : d.platform, lastSeen: d.lastUsed,
            added: d.createdAt, scopes: d.scopes, isThisMac: me)
    }

    /// The phones, iPads, Macs and browsers that only sign in: every active device that is not a runner.
    var signInMachines: [SignInMachine]? {
        guard service != nil, devices.load == .ready || !devices.items.isEmpty else { return nil }
        return devices.active.filter { $0.kind != "runner" }.map { Self.signIn($0, me: devices.isMe($0)) }
    }
}
