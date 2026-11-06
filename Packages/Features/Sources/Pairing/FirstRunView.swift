import CoreKit
import CoreUI
import CryptoKit
import Shell
import SwiftUI

/// The screen before the desktop: connect to a Core and pair this Mac with it.
struct FirstRunView: View {
    @Bindable var model: FirstRunModel
    @Environment(\.corePalette) private var palette
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduce
    /// What the field shows. The model keeps the formatted code; this follows it (the usual way to rewrite text while typing).
    @State private var codeField = ""
    @State private var pasteQR = false
    @State private var showKeys = false

    var body: some View {
        ZStack {
            Color.clear.overlay {
                Image(scheme == .dark ? "HomeSky" : "HomeSkyDay", bundle: .main).resizable().scaledToFill()
            }
            .clipped().accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if step.0 > 0 {
                    FirstRunHero(scene: heroScene, name: UserProfile.clean(model.nameText)).frame(maxWidth: .infinity)
                }
                Group {
                    switch model.stage {
                    case .form:
                        switch model.step {
                        case .name: nameStep
                        case .address: addressStep
                        case .bootstrap: bootstrapStep
                        case .code: form
                        }
                    case .claiming: claiming
                    case .sas: sas
                    case .approved: approved
                    case .failed(let f): failed(f)
                    }
                }
                .id("\(model.stage == .form ? "form" : "other")-\(model.step)")
                .transition(.opacity.combined(with: .offset(x: coreMove(reduce, 12))))

            }
            .foregroundStyle(palette.text)
            .font(.system(size: MacTextSize.body))
            .padding(Space.s6)
            .coreGlass(radius: Radius.panel, interactive: false)
            .frame(width: Space.s8 * 17)
            .accessibilityElement(children: .contain)
            cluster
        }
        .coreTheme()
        .onChange(of: codeField) { _, typed in
            model.typeCode(typed)
            if model.codeText != typed { codeField = model.codeText }
        }
        .onChange(of: model.codeText) { _, text in if text != codeField { codeField = text } }
        .onAppear {
            codeField = model.codeText
            pasteQR = model.usesQR
        }
        .animation(reduce ? .easeOut(duration: 0.2) : Motion.out(Motion.ui), value: model.stage)
        .animation(reduce ? .easeOut(duration: 0.2) : Motion.out(Motion.ui), value: model.step)
        .ignoresSafeArea()
    }

    private var step: (Int, String) {
        switch model.stage {
        case .form:
            switch model.step {
            case .name: (1, "Welcome")
            case .address, .bootstrap: (2, "Find your Core")
            case .code: (3, "Pair this Mac")
            }
        case .claiming, .sas: (3, "Pair this Mac")
        case .approved: (4, "Done")
        case .failed: (0, "Connect to a Core")
        }
    }

    private var heroScene: FirstRunHero.Scene {
        switch model.stage {
        case .form:
            switch model.step {
            case .name: .you
            case .address, .bootstrap: .find
            case .code: .key
            }
        case .claiming, .sas: .checking
        case .approved: .paired
        case .failed: .find
        }
    }

    private var header: some View {
        HStack(spacing: Space.s2) {
            Image("Emblem", bundle: .main).resizable().scaledToFit().frame(width: MacSize.controlMd)
                .accessibilityHidden(true)
            if step.0 > 0 {
                HStack(spacing: Space.s1) {
                    ForEach(1...4, id: \.self) { i in
                        coreShape(Radius.chip / 3).fill(i <= step.0 ? palette.primary : palette.track)
                            .frame(width: Space.s5, height: Space.s1)
                    }
                }
                .accessibilityHidden(true)
            }
            Text(step.1).font(.system(size: MacTextSize.meta, weight: .semibold)).foregroundStyle(palette.text2)
                .accessibilityLabel(step.0 > 0 ? "Step \(step.0) of 4, \(step.1)" : step.1)
        }
    }

    /// The status cluster of a Mac with no Core yet: nothing to be notified of, not connected.
    private var cluster: some View {
        HStack(spacing: Space.s1) {
            clusterItem("bell", nil, label: "Notifications")
            clusterItem("wifi.slash", "Not connected", label: "Not connected to a Core")
            Image("Emblem", bundle: .main).resizable().scaledToFit().frame(width: MacSize.controlMd - Space.s1)
                .frame(width: MacSize.controlLg, height: MacSize.controlLg).accessibilityHidden(true)
        }
        .padding(.horizontal, Space.s4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(.top, Space.s3)
    }

    private func clusterItem(_ symbol: String, _ title: String?, label: String) -> some View {
        HStack(spacing: Space.s1) {
            Image(systemName: symbol).accessibilityHidden(true)
            if let title { Text(title) }
        }
        .font(.system(size: MacTextSize.body))
        .padding(.horizontal, Space.s2).frame(minWidth: MacSize.controlMd, minHeight: MacSize.controlMd)
        .accessibilityElement(children: .combine).accessibilityLabel(label)
    }

    // MARK: form

    private var addressSuffix: String? {
        guard let url = try? EndpointInput.parse(model.endpointText), url.host != nil else { return nil }
        return "\(url.scheme ?? "https") · \(url.port ?? (url.scheme == "http" ? 80 : 443))"
    }

    private var keysHome: String { SecureEnclave.isAvailable ? "the Secure Enclave" : "this Mac's Keychain" }

    private func title(_ t: String) -> some View {
        Text(t).font(.system(size: MacTextSize.large, weight: .semibold)).accessibilityAddTraits(.isHeader)
    }

    private func note(_ t: LocalizedStringKey) -> some View {
        Text(t).foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
    }

    // MARK: step 1, who you are

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            title("Welcome to Ainkrad")
            note("What should we call you? Home greets you with it. It stays on this Mac.")
            CoreTextField(
                "Your name", placeholder: "Ahmed", text: $model.nameText, autofocus: true,
                onSubmit: { model.submitName() })
            HStack {
                Button("Not now") {
                    model.nameText = ""
                    model.submitName()
                }
                .coreGlassButton()
                .coreShortcut(.cancel)
                Spacer()
                Button("Continue") { model.submitName() }.coreGlassButton(prominent: true).coreShortcut(.primary)
            }
        }
    }

    // MARK: step 2, where the Core is

    private var addressStep: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            title("Where is your Core?")
            note(
                "Your Core is the server that runs your agents and terminals. This Mac connects to it to show you everything."
            )
            if let local = model.localCore, !pasteQR {
                foundLocalCore(local)
            }
            CoreSegmented(
                "How to connect",
                segments: [CoreSegment(false, "Type its address"), CoreSegment(true, "Paste a pairing link")],
                selection: Binding(get: { pasteQR }, set: { setQR($0) }), fill: true)
            if pasteQR {
                note(
                    "Copy the pairing link from the device that added this Mac. It already holds the address and the code."
                )
                CoreTextField(
                    "Pairing link", placeholder: "ainkrad-pair:v1?…", text: $codeField, error: model.codeError,
                    mono: true, autofocus: true, onSubmit: { Task { await model.submit() } })
            } else {
                CoreTextField(
                    "Core address", placeholder: "core.myhome.net", text: $model.endpointText,
                    error: model.endpointError, suffix: addressSuffix, onSubmit: { model.submitAddress() })
                Text("The address you gave your Core when you set it up. Add :port only if it uses one.")
                    .font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                LinkButton(title: "I don't have a Core yet") { model.goTo(.bootstrap) }
                Spacer()
                if pasteQR {
                    Button("Pair this Mac") { Task { await model.submit() } }
                        .coreGlassButton(prominent: true).coreShortcut(.primary).disabled(!model.canSubmit)
                } else {
                    Button("Continue") { model.submitAddress() }
                        .coreGlassButton(prominent: true).coreShortcut(.primary)
                        .disabled(model.endpointText.isEmpty)
                }
            }
        }
        .animation(.spring(duration: 0.4, bounce: 0.2), value: model.localCore)
        .task { await model.lookForLocalCore() }
    }

    /// A Core answered on this Mac: the easiest way in is one click.
    private func foundLocalCore(_ address: String) -> some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: MacTextSize.large))
                .foregroundStyle(palette.tone(.run).ink).symbolEffect(.bounce, value: address)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Found a Core on this Mac").font(.system(size: MacTextSize.body, weight: .semibold))
                Text(address).font(.system(size: MacTextSize.meta, design: .monospaced)).foregroundStyle(palette.text2)
            }
            Spacer(minLength: 0)
            Button("Use it") { model.useLocalCore() }.coreGlassButton(prominent: true)
        }
        .padding(Space.s3)
        .coreGlass(radius: Radius.control, interactive: false)
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
        .accessibilityElement(children: .combine)
    }

    private func setQR(_ on: Bool) {
        pasteQR = on
        model.typeCode("")
        codeField = ""
    }

    private var bootstrapStep: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            title("Setting up a new Core")
            note(
                "The very first device is created on the host itself, never over the network. Open a terminal on the machine that runs the Core."
            )
            Text("$ ainkrad bootstrap").font(.system(size: MacTextSize.body, design: .monospaced))
                .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.glassCard, in: coreShape(Radius.row))
            VStack(alignment: .leading, spacing: Space.s2) {
                note("1. Enter the address, then the code it printed.")
                note("2. Compare the check code on this Mac with the one the host prints, and type y there.")
                note("3. Add a second admin device (your iPhone) afterwards, so losing one never needs SSH.")
            }
            HStack {
                Button("Back") { model.goTo(.address) }.coreGlassButton().coreShortcut(.cancel)
                Spacer()
                Button("I have a code") { model.goTo(.address) }.coreGlassButton(prominent: true)
                    .coreShortcut(.primary)
            }
        }
    }

    // MARK: step 3, the pairing code

    private var form: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            title("Enter the pairing code")
            note("Ask an admin device to open **Add device**. The code is 10 characters and valid for 5 minutes.")
            CodeBoxes(
                label: "Pairing code", text: $codeField, error: model.codeError,
                onSubmit: { Task { await model.submit() } })
            Text("Case doesn't matter. I and L count as 1, O as 0.")
                .font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(spacing: Space.s1) {
                    Text("This Mac keeps its keys in \(keysHome)")
                    LinkButton(title: "Details", hint: "Shows which keys this Mac makes") { showKeys.toggle() }
                }
                if showKeys { keyDetails }
            }
            HStack {
                Button("Back") { model.goTo(.address) }.coreGlassButton().coreShortcut(.cancel)
                Spacer()
                Button("Pair this Mac") { Task { await model.submit() } }
                    .coreGlassButton(prominent: true).coreShortcut(.primary).disabled(!model.canSubmit)
            }
        }
    }

    private var keyDetails: some View {
        FactCard {
            FactRow(key: "Routine key", value: SecureEnclave.isAvailable ? "Secure Enclave" : "Software")
            FactRow(
                key: "Step-up key",
                value: SecureEnclave.isAvailable
                    ? "Secure Enclave, asks for Touch ID" : "None: it cannot unlock admin actions")
            FactRow(
                key: "Reported as", value: "key_storage = \(SecureEnclave.isAvailable ? "secure_enclave" : "software")",
                mono: true)
            Text(
                "The keys stay on this Mac. The Core only ever sees their public halves, and records the storage as a claim."
            )
            .font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var claiming: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text("Checking the Core").font(.system(size: MacTextSize.large, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Text(
                "Nothing is signed or sent from this Mac yet. The Core has to prove who it is first, then this Mac claims the code."
            )
            .foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
            IndBar().accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }

    // MARK: check code

    private var sas: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text("Compare this with the approver").font(.system(size: MacTextSize.large, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Text("It has to match the code on their screen, every character. If it doesn't, don't go on.")
                .foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
            if let claim = model.claim { SASView(sas: claim.sas) }
            statusLine
            HStack(spacing: Space.s2) {
                Button("It doesn't match") { Task { await model.cancel() } }
                    .coreGlassButton(prominent: true, tint: palette.tone(.fail).ink)
                    .coreShortcut(.number(1))
                Spacer(minLength: 0)
                if model.matched {
                    Button("Waiting…") {}.coreGlassButton(prominent: true).disabled(true)
                } else {
                    Button("It matches") { Task { await model.confirmMatch() } }
                        .coreGlassButton(prominent: true).coreShortcut(.primary)
                }
            }
        }
    }

    @ViewBuilder private var statusLine: some View {
        if model.approverApproved && !model.matched {
            Label("The approver approved. Say it matches to finish.", systemImage: "checkmark.seal")
                .font(.system(size: MacTextSize.body, weight: .semibold))
        } else {
            VStack(alignment: .leading, spacing: Space.s1) {
                IndBar().accessibilityHidden(true)
                Text("Waiting for approval").font(.system(size: MacTextSize.body, weight: .semibold))
                Text(
                    "A pairing lasts 5 minutes from when the approver made the code. This Mac isn't told the exact time."
                )
                .font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
                .fixedSize(horizontal: false, vertical: true)
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
                    if let n = model.displayName { FactRow(key: "You", value: n) }
                    if let e = model.endpoint { FactRow(key: "Core", value: e.absoluteString, mono: true) }
                    FactRow(
                        key: "Key storage",
                        value: SecureEnclave.isAvailable ? "Secure Enclave, routine and step-up" : "Keychain")
                    FactRow(key: "This Mac", value: claim.deviceID, mono: true)
                    FactRow(key: "Core fingerprint", value: String(claim.coreFingerprint.prefix(24)) + "…", mono: true)
                }
            }
            HStack {
                Spacer()
                Button("Open Ainkrad") { model.finish() }
                    .coreGlassButton(prominent: true).coreShortcut(.primary)
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
