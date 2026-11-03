import CoreKit
import CoreUI
import SwiftUI

/// The screen before the desktop: connect to a Core and pair this Mac with it.
struct FirstRunView: View {
    @Bindable var model: FirstRunModel
    @Environment(\.corePalette) private var palette
    @Environment(\.colorScheme) private var scheme
    /// What the field shows. The model keeps the formatted code; this follows it (the usual way to rewrite text while typing).
    @State private var codeField = ""

    var body: some View {
        ZStack {
            Color.clear.overlay {
                Image(scheme == .dark ? "HomeSky" : "HomeSkyDay", bundle: .main).resizable().scaledToFill()
            }
            .clipped().accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                switch model.stage {
                case .form: form
                case .claiming: claiming
                case .sas: sas
                case .approved: approved
                case .failed(let f): failed(f)
                }
            }
            .foregroundStyle(palette.text)
            .font(.system(size: MacTextSize.body))
            .corePanel(radius: Radius.panel, padding: Space.s6)
            .overlay { coreShape(Radius.panel).strokeBorder(palette.glassCardEdge, lineWidth: 1) }
            .frame(width: Space.s8 * 17)
            .accessibilityElement(children: .contain)
        }
        .coreTheme()
        .onChange(of: codeField) { _, typed in
            model.typeCode(typed)
            if model.codeText != typed { codeField = model.codeText }
        }
        .onChange(of: model.codeText) { _, text in if text != codeField { codeField = text } }
        .onAppear { codeField = model.codeText }
        .animation(Motion.out(Motion.ui), value: model.stage)
        .ignoresSafeArea()
    }

    private var step: (Int, String) {
        switch model.stage {
        case .form, .claiming: (1, "Find your Core")
        case .sas: (2, "Pair this Mac")
        case .approved: (3, "Done")
        case .failed: (0, "Connect to a Core")
        }
    }

    private var header: some View {
        HStack(spacing: Space.s2) {
            Image("Emblem", bundle: .main).resizable().scaledToFit().frame(width: MacSize.controlMd)
                .accessibilityHidden(true)
            if step.0 > 0 {
                HStack(spacing: Space.s1) {
                    ForEach(1...3, id: \.self) { i in
                        coreShape(Radius.chip / 3).fill(i <= step.0 ? palette.primary : palette.track)
                            .frame(width: Space.s5, height: Space.s1)
                    }
                }
                .accessibilityHidden(true)
            }
            Text(step.0 > 0 ? "Step \(step.0) of 3 · \(step.1)" : step.1)
                .font(.system(size: MacTextSize.meta, weight: .semibold)).foregroundStyle(palette.text2)
        }
    }

    // MARK: form

    private var form: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text("Connect to a Core").font(.system(size: MacTextSize.large, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Text(
                "Enter your Core's address and the pairing code from an admin device. Ainkrad Core checks who answers before it sends anything signed."
            )
            .foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
            if model.usesQR {
                Label("This QR names its Core and its fingerprint, so no address is needed.", systemImage: "qrcode")
                    .foregroundStyle(palette.text2)
            } else {
                FieldBox(
                    label: "Core address", placeholder: "core.example.net or http://127.0.0.1:7700",
                    text: $model.endpointText, error: model.endpointError, onSubmit: { Task { await model.submit() } })
            }
            FieldBox(
                label: "Pairing code or QR text", placeholder: "ABCDE-FGHJK",
                text: $codeField, error: model.codeError,
                mono: true, onSubmit: { Task { await model.submit() } })
            Text(
                "Case does not matter. I and L count as 1, O as 0. To use a QR, paste the text it holds. Plain http is only for a Core on this Mac."
            )
            .font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Pair this Mac") { Task { await model.submit() } }
                    .buttonStyle(.coreProminent).keyboardShortcut(.defaultAction).disabled(!model.canSubmit)
            }
        }
    }

    private var claiming: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text("Checking the Core").font(.system(size: MacTextSize.large, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: Space.s3) {
                Spin()
                Text("The Core has to prove who it is first. Then this Mac claims the code.")
                    .foregroundStyle(palette.text2)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.updatesFrequently)
        }
    }

    // MARK: check code

    private var sas: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text("Compare this with the approver").font(.system(size: MacTextSize.large, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Text("It has to match the code on their screen, every character. If it doesn't, do not go on.")
                .foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
            if let claim = model.claim { SASView(sas: claim.sas) }
            statusLine
            HStack(spacing: Space.s2) {
                Spacer(minLength: 0)
                if model.matched {
                    Button("Cancel pairing") { Task { await model.cancel() } }.buttonStyle(.coreSecondary)
                    Button("Waiting…") {}.buttonStyle(CoreButtonStyle(.prominent, busy: true)).disabled(true)
                } else {
                    Button("It doesn't match") { Task { await model.cancel() } }.buttonStyle(.coreSecondary)
                    Button("It matches") { Task { await model.confirmMatch() } }
                        .buttonStyle(.coreProminent).keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    @ViewBuilder private var statusLine: some View {
        if model.approverApproved && !model.matched {
            Label("The approver approved. Say it matches to finish.", systemImage: "checkmark.seal")
                .font(.system(size: MacTextSize.body, weight: .semibold))
        } else {
            HStack(spacing: Space.s2) {
                Spin()
                VStack(alignment: .leading, spacing: 0) {
                    Text("Waiting for approval").font(.system(size: MacTextSize.body, weight: .semibold))
                    Text("A pairing lasts 5 minutes from when the approver made the code.")
                        .font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.updatesFrequently)
        }
    }

    // MARK: done

    private var approved: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            HStack(spacing: Space.s3) {
                Image(systemName: "checkmark").font(.system(size: MacTextSize.large))
                    .foregroundStyle(palette.tone(.run).ink)
                    .frame(width: MacSize.controlLg, height: MacSize.controlLg)
                    .background(palette.tone(.run).fill, in: coreShape(Radius.control)).accessibilityHidden(true)
                Text("This Mac is paired").font(.system(size: MacTextSize.large, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
            }
            Text("The Core approved it. You are signed in, and the session renews itself in the background.")
                .foregroundStyle(palette.text2)
            if let claim = model.claim {
                FactCard {
                    if let e = model.endpoint { FactRow(key: "Core", value: e.absoluteString, mono: true) }
                    FactRow(key: "This Mac", value: claim.deviceID, mono: true)
                    FactRow(key: "Core fingerprint", value: String(claim.coreFingerprint.prefix(24)) + "…", mono: true)
                }
            }
            HStack {
                Spacer()
                Button("Open Ainkrad Core") { model.finish() }
                    .buttonStyle(.coreProminent).keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: failures

    private func failed(_ f: Failure) -> some View {
        let start = FailureAction(label: "Start over", style: .primary) { model.reset() }
        let retry = FailureAction(label: "Try again", style: .primary, disabled: false) {
            Task { await model.submit() }
        }
        let edit = FailureAction(label: "Edit address") { model.editAddress() }
        let actions: [FailureAction]
        switch f.kind {
        case .offline, .unproven, .other, .clockSkew, .rateLimited:
            actions = model.endpoint == nil && model.usesQR ? [retry] : [edit, retry]
        default: actions = [start]
        }
        return FailureView(failure: f, retryAt: model.retryAt, actions: actions)
    }
}
