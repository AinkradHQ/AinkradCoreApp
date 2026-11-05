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
        DialogCard(title: "What \(device.name) may do", width: Space.s8 * 15, close: { app.shell.closeDialog() }) {
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
                            locked: device.scopes.contains(s) ? nil : "Can't be added. Pair again for more access.")
                    }
                }
                ScopeWarnings(app: app, device: device, kept: on)
                StepUpBanner(app: app)
                ErrorLine(text: app.devices.dialogError)
                DialogButtons(
                    app: app, confirm: "Save", busy: app.devices.busy,
                    enabled: device.kind != "runner" && on != Set(device.scopes) && !on.isEmpty
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

/// What taking scopes away does, live as the boxes change: each line has a symbol and words, never a colour alone.
struct ScopeWarnings: View {
    let app: AppModel
    let device: DeviceInfo
    let kept: Set<String>
    @Environment(\.corePalette) private var palette

    private var lines: [(tone: Tone, symbol: String, text: String)] {
        let gone = Set(device.scopes).subtracting(kept)
        var out: [(Tone, String, String)] = []
        if gone.contains("admin") {
            if app.devices.onlyAdmin?.id == device.id {
                out.append(
                    (
                        .fail, "xmark.octagon",
                        "\(device.name) is the last admin. The Core will refuse this (409 conflict)."
                    ))
            } else {
                out.append((.warn, "exclamationmark.triangle", "It can no longer manage devices, secrets or settings."))
            }
        }
        if gone.contains("approve") {
            out.append(
                (
                    .warn, "exclamationmark.triangle",
                    "It can no longer decide agent approvals. Waiting ones need another device."
                ))
        }
        if gone.contains("read") {
            out.append(
                (.warn, "exclamationmark.triangle", "Without read it can't load anything, not even its own session."))
        }
        if !gone.isEmpty {
            out.append(
                (
                    .queue, "clock",
                    "Open connections from this device close right away (4003) and reconnect with the new access."
                ))
        }
        if kept.isEmpty {
            out.append((.fail, "xmark.octagon", "A device needs at least one scope. To remove it, revoke it."))
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, l in
                Label {
                    Text(l.text).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: l.symbol).foregroundStyle(palette.tone(l.tone).ink)
                }
                .font(.system(size: MacTextSize.body))
            }
        }
        .animation(Motion.out(Motion.ui), value: lines.map(\.text))
        .accessibilityElement(children: .contain)
    }
}

struct RevokeDialog: View {
    let app: AppModel
    let device: DeviceInfo
    @Environment(\.corePalette) private var palette

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
                FactCard {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Access it loses").foregroundStyle(palette.text2)
                        Spacer(minLength: Space.s3)
                        AccessChips(scopes: device.scopes)
                    }
                    FactRow(key: "Needs", value: "Touch ID, if locked")
                }
                if me {
                    Text("You will be signed out of this Mac and sent back to Connect.")
                        .font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
                }
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
