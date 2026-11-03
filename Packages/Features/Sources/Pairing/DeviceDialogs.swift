import CoreUI
import Shell
import SwiftUI

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
            if destructive {
                Button(confirm, action: run).buttonStyle(DangerButtonStyle()).disabled(!enabled || busy)
            } else {
                Button(confirm, action: run).buttonStyle(CoreButtonStyle(.prominent, busy: busy))
                    .keyboardShortcut(.defaultAction).disabled(!enabled)
            }
        }
    }
}

struct ErrorLine: View {
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
            StepUpBanner(app: app)
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
                StepUpBanner(app: app)
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
                StepUpBanner(app: app)
                ErrorLine(text: app.devices.dialogError)
                DialogButtons(app: app, confirm: "Revoke", destructive: true, busy: app.devices.busy) {
                    Task { if await app.devices.revoke(device) { app.shell.closeDialog() } }
                }
            }
            .font(.system(size: MacTextSize.body))
        }
    }
}
