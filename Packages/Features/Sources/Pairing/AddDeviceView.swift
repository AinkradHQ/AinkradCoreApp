import AppKit
import CoreUI
import Shell
import SwiftUI

struct AddDeviceView: View {
    let app: AppModel
    @Bindable var model: AddDeviceModel
    let close: () -> Void
    @Environment(\.corePalette) private var palette

    var body: some View {
        DialogCard(title: title, width: Space.s8 * 16, close: close) {
            VStack(alignment: .leading, spacing: Space.s4) {
                switch model.stage {
                case .form, .creating: form
                case .code(let p): code(p)
                case .claimed(let info): claimed(info)
                case .approved(let info): approved(info)
                case .ended(let why): ended(why)
                }
                StepUpBanner(app: app)
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
        case .form, .creating: "Add a device"
        case .code: "Pair a new device"
        case .claimed: "A device wants to join"
        case .approved: "Device paired"
        case .ended(let why):
            why == "rejected"
                ? "Pairing rejected" : why == "burned" ? "Every live pairing was cancelled" : "The pairing expired"
        }
    }

    // MARK: form

    private var form: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text("This Mac creates a one-time code. Whoever enters it still needs your approval.")
                .foregroundStyle(palette.text2)
            CoreTextField("Device name", placeholder: "iPhone, linux-01…", text: $model.name, autofocus: true) {
                Task { await model.create() }
            }
            CoreSegmented(
                "Kind", segments: [CoreSegment("device", "Device"), CoreSegment("runner", "Runner")],
                selection: $model.kind)
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("Access narrowed from your own. You can only give less.").font(
                    .system(size: MacTextSize.meta, weight: .semibold)
                ).foregroundStyle(palette.text2)
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
                Text("Lasts 5 minutes · single use").font(.system(size: MacTextSize.meta))
                    .foregroundStyle(palette.text2)
                Spacer(minLength: 0)
                Button("Cancel", action: close).buttonStyle(.coreSecondary).keyboardShortcut(.cancelAction)
                Button("Create pairing") { Task { await model.create() } }
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
                    Text("Type this code on the new device").font(.system(size: MacTextSize.meta, weight: .semibold))
                        .foregroundStyle(palette.text2)
                    CodeCells(code: Self.shown(p.code))
                    if let fp = app.coreFingerprint {
                        VStack(alignment: .leading, spacing: Space.s1) {
                            Text("Core fingerprint").font(.system(size: MacTextSize.meta, weight: .semibold))
                                .foregroundStyle(palette.text2)
                            Text(String(fp.prefix(24)) + "…")
                                .font(.system(size: MacTextSize.body, design: .monospaced)).textSelection(.enabled)
                        }
                    }
                    expiry(p)
                    HStack(spacing: Space.s2) {
                        Button("Copy code") { copy(p.code) }.buttonStyle(.coreSecondary)
                        if let qr = p.qr { Button("Copy QR text") { copy(qr) }.buttonStyle(.coreSecondary) }
                    }
                }
                if let qr = p.qr { QRImage(text: qr).frame(width: Space.s8 * 5, height: Space.s8 * 5) }
            }
            VStack(alignment: .leading, spacing: Space.s1) {
                IndBar()
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

    /// Time left as words and a bar that shrinks; amber in the last minute.
    private func expiry(_ p: NewPairing) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let left = max(0, Int((p.expiresAt ?? ctx.date).timeIntervalSince(ctx.date).rounded(.up)))
            let soon = left <= 60
            VStack(alignment: .leading, spacing: Space.s1) {
                HStack(spacing: Space.s2) {
                    Image(systemName: soon ? "exclamationmark.triangle" : "clock").accessibilityHidden(true)
                    Text(left > 0 ? "Expires in \(Countdown.text(left))" : "Expired")
                        .font(.system(size: MacTextSize.body, weight: .semibold).monospacedDigit())
                }
                .foregroundStyle(soon ? palette.tone(.warn).ink : palette.text2)
                CoreMeter(Double(left) / 300, low: soon, label: "Code time left")
            }
        }
    }

    // MARK: claimed

    private func claimed(_ info: PairingInfo) -> some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text("Check the details, then compare the code with the one on the new device.")
                .foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
            FactCard {
                FactRow(key: "Name", value: info.name ?? "Unnamed")
                FactRow(key: "Platform", value: DeviceWords.platform(info.platform))
                FactRow(key: "Key storage", value: DeviceWords.storage(info.keyStorage))
                FactRow(key: "Will get", value: info.scopes.joined(separator: ", "), mono: true)
                if let until = info.expiresAt {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        let left = max(0, Int(until.timeIntervalSince(ctx.date).rounded(.up)))
                        FactRow(key: "Expires in", value: Countdown.text(left), mono: true)
                    }
                }
            }
            Text("The Core computed this code. The new device must show the same one.")
                .foregroundStyle(palette.text2)
            if let sas = info.sas { SASView(sas: sas, matched: model.groupsMatching) }
            checkProgress
            CoreTextField(
                "Type it here to confirm they match", placeholder: "XXXX-XXXX-XXXX-XXXX", text: $model.typed,
                mono: true, autofocus: true
            ) {
                if model.checkMatches { Task { await model.approve() } }
            }
            .accessibilityIdentifier("check-code-field")
            Text("Typing it proves you looked at this device's own screen.")
                .font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
            HStack(spacing: Space.s2) {
                Spacer(minLength: 0)
                Button("Reject") { Task { await model.reject() } }.buttonStyle(.coreSecondary).disabled(model.busy)
                Button("Approve") { Task { await model.approve() } }
                    .buttonStyle(CoreButtonStyle(.prominent, busy: model.busy)).keyboardShortcut(.defaultAction)
                    .disabled(!model.checkMatches)
            }
        }
    }

    /// What the typing says so far, in words and a symbol: groups matched, the next one, or a mismatch.
    @ViewBuilder private var checkProgress: some View {
        let n = model.groupsMatching
        let total = model.groupCount
        if model.checkMismatch {
            VStack(alignment: .leading, spacing: Space.s1 / 2) {
                Label("That doesn't match", systemImage: "xmark.octagon").fontWeight(.semibold)
                Text("The device stays pending. Read the new device's screen again and retype it, or reject it.")
                    .foregroundStyle(palette.text2)
            }
            .foregroundStyle(palette.tone(.fail).ink)
        } else if model.checkMatches {
            Label("All \(total) groups match.", systemImage: "checkmark.circle")
                .foregroundStyle(palette.tone(.done).ink)
        } else {
            Label(
                n == 0 ? "Type group 1 of \(total)." : "\(n) of \(total) groups match, now group \(n + 1).",
                systemImage: "keyboard"
            )
            .foregroundStyle(palette.text2)
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
                Button("Close", action: close).buttonStyle(.coreSecondary).keyboardShortcut(.cancelAction)
                Button("Create a new pairing") { model.restart() }.buttonStyle(.coreProminent)
                    .keyboardShortcut(.defaultAction)
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

/// The pairing code as ten cells in two groups. Each settles in 50 ms after the one before; Reduce Motion shows them at once.
private struct CodeCells: View {
    let code: String
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var settled = false

    var body: some View {
        HStack(spacing: Space.s1) {
            ForEach(Array(code.enumerated()), id: \.offset) { i, ch in
                if ch == "-" {
                    Spacer().frame(width: Space.s2)
                } else {
                    Text(String(ch))
                        .font(.system(size: MacTextSize.large, weight: .semibold, design: .monospaced))
                        .frame(width: MacSize.controlLg, height: MacSize.controlLg + Space.s3)
                        .background(palette.glassCard, in: coreShape(Radius.control))
                        .overlay { coreShape(Radius.control).strokeBorder(palette.glassCardEdge, lineWidth: 1) }
                        .opacity(settled || reduce ? 1 : 0)
                        .offset(y: settled || reduce ? 0 : 6)
                        .animation(Motion.out(Motion.ui).delay(Double(i) * 0.05), value: settled)
                }
            }
        }
        .onAppear { settled = true }
        .textSelection(.enabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pairing code \(code.filter { $0 != "-" }.map { String($0) }.joined(separator: " "))")
        .accessibilityIdentifier("pairing-code")
    }
}
