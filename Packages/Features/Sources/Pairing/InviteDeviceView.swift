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

    var body: some View {
        DialogCard(title: "Add a device", width: Space.s8 * 24, close: { attemptClose() }) {
            VStack(alignment: .leading, spacing: Space.s4) {
                Text("Scan this on the new device. It connects directly; there is nothing to approve afterwards.")
                    .foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .top, spacing: Space.s5) {
                    qr
                    form.disabled(model.busy)
                }
                if let invite = model.invite, !model.used, !model.ended { linkRow(invite) }
                StepUpBanner(app: app)
                if model.stillLive { stillLiveNotice }
                if let e = model.error {
                    Label(e, systemImage: "exclamationmark.triangle").foregroundStyle(palette.tone(.fail).ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: Space.s2) {
                    LinkButton(title: "Use a typed code instead", action: typedCode)
                    Spacer(minLength: 0)
                    if model.invite?.pairingID != nil, !model.used, !model.ended {
                        Button("Withdraw") { Task { await model.withdraw() } }
                            .buttonStyle(.coreSecondary).disabled(model.busy)
                    }
                    Button(model.invite == nil ? "Show QR" : "New code") { Task { await model.create() } }
                        .buttonStyle(CoreButtonStyle(model.invite == nil ? .prominent : .secondary, busy: model.busy))
                        .disabled(!model.canCreate)
                    Button("Done") { attemptClose() }.buttonStyle(.coreProminent).coreShortcut(.primary)
                }
            }
            .coreFont(size: MacTextSize.body)
        }
        .task { await model.prepare() }
        .background(WindowSharingGuard())
        .task(id: model.invite) {
            // A claimed invite is `approved` at once; the poll covers a dropped event stream.
            while !Task.isCancelled, model.invite != nil, !model.used, !model.ended {
                try? await Task.sleep(for: .seconds(2))
                await model.refresh()
            }
        }
    }

    /// Closing with Done or the close button needs the QR withdrawn first (Touch ID once the window has run out).
    private func attemptClose() {
        Task { if await model.requestClose() { close() } }
    }

    private var stillLiveNotice: some View {
        CoreNotice(
            symbol: "exclamationmark.triangle", title: "This QR is still live",
            text: "Anyone who scans it can add a device. Withdraw it?",
            tone: .warn
        ) {
            HStack(spacing: Space.s2) {
                Button("Withdraw") { attemptClose() }.buttonStyle(.coreSecondary).disabled(model.busy)
                Button("Close anyway") {
                    model.abandon()
                    close()
                }
                .buttonStyle(.coreSecondary)
            }
        }
    }

    private var qr: some View {
        Group {
            if model.used {
                spent("checkmark", "\(model.invite?.name ?? "The device") is connected", palette.tone(.done).ink)
            } else if model.ended {
                spent("xmark", "This QR was withdrawn", palette.text2)
            } else if let invite = model.invite {
                QRImage(text: invite.link.text)
            } else {
                coreShape(Radius.cardMac).fill(palette.glassCard)
                    .overlay { if model.busy { CoreBusyBar().padding(Space.s4) } }
            }
        }
        .frame(width: Space.s8 * 6, height: Space.s8 * 6)
        .accessibilityIdentifier("invite-qr")
    }

    /// A used or withdrawn QR is replaced by a plain statement; the secret is not drawn any more.
    private func spent(_ symbol: String, _ words: String, _ ink: Color) -> some View {
        VStack(spacing: Space.s2) {
            Image(systemName: symbol).coreFont(size: MacTextSize.large, weight: .semibold).foregroundStyle(ink)
                .accessibilityHidden(true)
            Text(words).coreFont(size: MacTextSize.body, weight: .semibold).multilineTextAlignment(.center)
        }
        .padding(Space.s3).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.glassCard, in: coreShape(Radius.cardMac))
        .accessibilityElement(children: .combine)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            CoreTextField("Device name", placeholder: "iPhone", text: $model.name).disabled(model.busy)
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
            Button(model.copied ? "Copied" : "Copy link") { model.copyLink() }
                .buttonStyle(.coreSecondary)
                .accessibilityHint("Copies the link and its one-time secret; cleared after a minute.")
        }
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.glassCard, in: coreShape(Radius.row))
    }
}
