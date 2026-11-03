import AppKit
import CoreUI
import SwiftUI

struct AddDeviceView: View {
    @Bindable var model: AddDeviceModel
    let close: () -> Void
    @Environment(\.corePalette) private var palette

    var body: some View {
        DialogCard(title: title, width: Space.s8 * 16) {
            VStack(alignment: .leading, spacing: Space.s4) {
                switch model.stage {
                case .form, .creating: form
                case .code(let p): code(p)
                case .claimed(let info): claimed(info)
                case .approved(let info): approved(info)
                case .ended(let why): ended(why)
                }
                if let e = model.error {
                    Label(e, systemImage: "exclamationmark.triangle").foregroundStyle(palette.tone(.fail).ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(.system(size: MacTextSize.body))
        }
        .task { await model.prepare() }
        .task(id: model.pairingID) {
            // The Core's events refresh this at once; the poll covers a dropped event stream.
            while !Task.isCancelled, model.pairingID != nil {
                try? await Task.sleep(for: .seconds(2))
                await model.refresh()
            }
        }
    }

    private var title: String {
        switch model.stage {
        case .form, .creating: "Add device"
        case .code: "Pair a new device"
        case .claimed: "A device wants to join"
        case .approved: "Device paired"
        case .ended: "Pairing ended"
        }
    }

    // MARK: form

    private var form: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text("Name the device, choose what it may do, and you get a code that lasts 5 minutes.")
                .foregroundStyle(palette.text2)
            FieldBox(label: "Device name", placeholder: "iPhone, linux-01…", text: $model.name, autofocus: true) {
                Task { await model.create() }
            }
            CoreSegmented(
                "Kind", segments: [CoreSegment("device", "Device"), CoreSegment("runner", "Runner")],
                selection: $model.kind)
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("It may").font(.system(size: MacTextSize.meta, weight: .semibold)).foregroundStyle(palette.text2)
                if model.kind == "runner" {
                    Text("A runner holds exactly runner: it only redeems secret leases.").foregroundStyle(palette.text2)
                } else {
                    ForEach(ScopeText.all, id: \.self) { s in
                        ScopeToggle(
                            scope: s,
                            on: Binding(
                                get: { model.scopes.contains(s) },
                                set: { if $0 { model.scopes.insert(s) } else { model.scopes.remove(s) } }),
                            locked: model.mine.contains(s) ? nil : "This Mac does not hold it, so it cannot hand it on."
                        )
                    }
                }
            }
            HStack(spacing: Space.s2) {
                Spacer(minLength: 0)
                Button("Cancel", action: close).buttonStyle(.coreSecondary).keyboardShortcut(.cancelAction)
                Button("Make code") { Task { await model.create() } }
                    .buttonStyle(CoreButtonStyle(.prominent, busy: model.stage == .creating))
                    .keyboardShortcut(.defaultAction).disabled(!model.canCreate)
            }
        }
    }

    // MARK: code

    private func code(_ p: NewPairing) -> some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text("On the new device, choose Connect to a Core and enter this code, or scan the QR.")
                .foregroundStyle(palette.text2)
            HStack(alignment: .top, spacing: Space.s5) {
                VStack(alignment: .leading, spacing: Space.s3) {
                    Text(Self.shown(p.code)).font(
                        .system(size: MacTextSize.large * 1.6, weight: .semibold, design: .monospaced)
                    )
                    .textSelection(.enabled).accessibilityLabel(
                        "Pairing code \(p.code.map { String($0) }.joined(separator: " "))"
                    )
                    .accessibilityIdentifier("pairing-code")
                    expiry(p)
                    HStack(spacing: Space.s2) {
                        Button("Copy code") { copy(p.code) }.buttonStyle(.coreSecondary)
                        if let qr = p.qr { Button("Copy QR text") { copy(qr) }.buttonStyle(.coreSecondary) }
                    }
                }
                if let qr = p.qr { QRImage(text: qr).frame(width: Space.s8 * 5, height: Space.s8 * 5) }
            }
            HStack(spacing: Space.s2) {
                Spin()
                Text("Waiting for the new device to claim it").font(.system(size: MacTextSize.body, weight: .semibold))
            }
            .accessibilityElement(children: .combine).accessibilityAddTraits(.updatesFrequently)
            HStack {
                Spacer()
                Button("Cancel pairing") { Task { await model.reject() } }.buttonStyle(.coreSecondary)
                Button("Close", action: close).buttonStyle(.coreSecondary).keyboardShortcut(.cancelAction)
            }
        }
    }

    private func expiry(_ p: NewPairing) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let left = max(0, Int((p.expiresAt ?? ctx.date).timeIntervalSince(ctx.date).rounded(.up)))
            HStack(spacing: Space.s2) {
                Image(systemName: "clock").accessibilityHidden(true)
                Text(left > 0 ? "Expires in \(left / 60):\(String(format: "%02d", left % 60))" : "Expired")
                    .font(.system(size: MacTextSize.body, weight: .semibold).monospacedDigit())
            }
            .foregroundStyle(left > 0 ? palette.text2 : palette.tone(.warn).ink)
        }
    }

    // MARK: claimed

    private func claimed(_ info: PairingInfo) -> some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text(
                "Compare this with the check code on the new device's screen. Approve only if every character matches."
            )
            .foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
            FactCard {
                FactRow(key: "Name", value: info.name ?? "Unnamed")
                FactRow(key: "Platform", value: DeviceWords.platform(info.platform))
                FactRow(key: "Key storage", value: DeviceWords.storage(info.keyStorage))
                FactRow(key: "May", value: info.scopes.joined(separator: ", "), mono: true)
            }
            if let sas = info.sas { SASView(sas: sas) }
            HStack(spacing: Space.s2) {
                Spacer(minLength: 0)
                Button("Reject") { Task { await model.reject() } }.buttonStyle(.coreSecondary).disabled(model.busy)
                Button("It matches, approve") { Task { await model.approve() } }
                    .buttonStyle(CoreButtonStyle(.prominent, busy: model.busy)).keyboardShortcut(.defaultAction)
            }
        }
    }

    private func approved(_ info: PairingInfo) -> some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Label("\(info.name ?? "The device") is paired.", systemImage: "checkmark")
                .font(.system(size: MacTextSize.headline, weight: .semibold))
            Text("It finishes on the new device once it confirms the check code there.").foregroundStyle(palette.text2)
            HStack {
                Spacer()
                Button("Done", action: close).buttonStyle(.coreProminent).keyboardShortcut(.defaultAction)
            }
        }
    }

    private func ended(_ why: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text(
                why == "rejected"
                    ? "The pairing was rejected. Its keys were never enrolled."
                    : why == "burned"
                        ? "Too many wrong codes burned this pairing. Make a new one."
                        : "The pairing expired. Make a new code."
            )
            .foregroundStyle(palette.text2)
            HStack {
                Spacer()
                Button("Close", action: close).buttonStyle(.coreProminent).keyboardShortcut(.defaultAction)
            }
        }
    }

    static func shown(_ code: String) -> String {
        code.contains("-") || code.count != 10 ? code : "\(code.prefix(5))-\(code.dropFirst(5))"
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
