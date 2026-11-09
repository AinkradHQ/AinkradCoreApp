import AppKit
import CoreUI
import Shell
import SwiftUI

/// Add device by QR: the code on the left, what the device may do on the right.
struct InviteDeviceView: View {
    let app: AppModel
    @Bindable var model: InviteDeviceModel
    let close: () -> Void
    let typedCode: () -> Void
    @Environment(\.corePalette) private var palette
    @State private var copied = false

    var body: some View {
        DialogCard(title: "Add a device", width: Space.s8 * 19, close: close) {
            VStack(alignment: .leading, spacing: Space.s4) {
                Text("Scan this on the new device. It connects directly; there is nothing to approve afterwards.")
                    .foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .top, spacing: Space.s5) {
                    qr
                    form
                }
                if let invite = model.invite { linkRow(invite) }
                StepUpBanner(app: app)
                if let e = model.error {
                    Label(e, systemImage: "exclamationmark.triangle").foregroundStyle(palette.tone(.fail).ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: Space.s2) {
                    LinkButton(title: "Use a typed code instead", action: typedCode)
                    Spacer(minLength: 0)
                    Button(model.invite == nil ? "Make QR" : "New code") { Task { await model.create() } }
                        .buttonStyle(CoreButtonStyle(model.invite == nil ? .prominent : .secondary, busy: model.busy))
                        .disabled(!model.canCreate)
                    Button("Done", action: close).buttonStyle(.coreProminent).coreShortcut(.primary)
                }
            }
            .coreFont(size: MacTextSize.body)
        }
        .task { await model.quick() }
    }

    private var qr: some View {
        Group {
            if let invite = model.invite {
                QRImage(text: invite.link.text)
            } else {
                coreShape(Radius.cardMac).fill(palette.glassCard)
                    .overlay { if model.busy { CoreBusyBar().padding(Space.s4) } }
            }
        }
        .frame(width: Space.s8 * 6, height: Space.s8 * 6)
        .accessibilityIdentifier("invite-qr")
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            CoreTextField("Device name", placeholder: "iPhone", text: $model.name)
            Text("What it may do. You can only give what this Mac holds.").coreFont(
                size: MacTextSize.meta, weight: .semibold
            ).foregroundStyle(palette.text2)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.s2), GridItem(.flexible())], spacing: Space.s2) {
                ForEach(Array(ScopeText.all.enumerated()), id: \.element) { i, s in
                    ScopeToggle(
                        scope: s,
                        on: Binding(
                            get: { model.scopes.contains(s) },
                            set: { if $0 { model.scopes.insert(s) } else { model.scopes.remove(s) } }),
                        locked: model.mine.isEmpty || model.mine.contains(s)
                            ? nil : "This Mac does not hold it, so it cannot hand it on.", index: i)
                }
            }
            Text("One use. It stays valid until a device scans it. Revoke the device later from Devices.")
                .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func linkRow(_ invite: DeviceInvite) -> some View {
        HStack(spacing: Space.s2) {
            Text("\(invite.link.address) · \(invite.link.fingerprintHint)")
                .coreFont(size: MacTextSize.body, design: .monospaced).foregroundStyle(palette.text2)
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
            Button(copied ? "Copied" : "Copy link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(invite.link.text, forType: .string)
                copied = true
            }
            .buttonStyle(.coreSecondary).accessibilityHint("Copies the connect link, including its one-time secret")
        }
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.glassCard, in: coreShape(Radius.row))
        .onChange(of: invite) { copied = false }
    }
}
