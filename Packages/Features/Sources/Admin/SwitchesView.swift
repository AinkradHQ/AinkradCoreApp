import CoreUI
import SwiftUI

/// Settings, Core, Feature switches: the settings that gate a feature, each with the steps between its states.
struct SwitchesSection: View {
    let admin: AdminModel
    @Environment(\.corePalette) private var palette

    var body: some View {
        let model = admin.registry
        AdminScreen(
            admin: admin, what: "Feature switches",
            intro:
                "Turn Core features on or off. Each change asks for Touch ID and is written to the audit log.",
            state: model.state,
            empty: ("No switches reported", "The registry returned no feature switches.", "switch.2"),
            retry: { Task { await model.reload() } }
        ) {
            VStack(alignment: .leading, spacing: Space.s4) {
                AdminNoticeBanner(notice: admin.host.elevationNotice)
                if let mode = model.item("secrets.mode") { SecretsModeCard(model: model, setting: mode) }
                if let a = model.item("secrets.provider_accounts") {
                    FlagCard(
                        model: model, setting: a, index: 1, title: "Real provider keys", symbol: "key.fill",
                        hue: GlassInk.orange,
                        sub: "Let accounts hold a real API key from Anthropic, OpenAI or Google.",
                        offLine: "Only test keys are accepted for accounts.",
                        onLine: "Accounts can hold real provider keys. Your agents can use them.",
                        needs: model.secretsMode < 1 ? "Set Keys and secrets to Test keys first." : nil,
                        reason: {
                            $0 ? "Let accounts hold real provider keys." : "Stop accounts holding real provider keys."
                        })
                }
                if let c = model.item("secrets.connections") {
                    FlagCard(
                        model: model, setting: c, index: 2, title: "Real connection tokens", symbol: "link",
                        hue: GlassInk.orange,
                        sub: "Let a connection to GitHub, Jira or Linear hold its own real token.",
                        offLine: "Connections accept test tokens only.",
                        onLine:
                            "A connection can hold one real token of its own service. Real keys for other things stay refused.",
                        needs: RegistryModel.connectionsNeeds(mode: model.secretsMode),
                        reason: {
                            $0 ? "Let connections hold their own real tokens." : "Stop connections holding real tokens."
                        })
                }
                if let p = model.item("auth.passkey_admin") {
                    FlagCard(
                        model: model, setting: p, index: 3, title: "Admin from a browser", symbol: "globe",
                        hue: GlassInk.violet,
                        sub: "Let a device that signs in with a passkey in a web browser become an admin.",
                        offLine: "Browser devices can read and approve, but not change your Core. Safer.",
                        onLine:
                            "Browser devices can become admin. Someone who steals that browser could change your Core.",
                        needs: nil,
                        reason: {
                            $0
                                ? "Let browser devices become admin. A stolen passkey session could then hold admin."
                                : "Stop browser devices becoming admin."
                        })
                }
                if !model.runners.isEmpty {
                    GlassSection(
                        "Terminals on your runners",
                        sub: "Whether each runner can open terminals.",
                        symbol: "terminal.fill", hue: GlassInk.green, index: 4
                    ) {
                        ForEach(model.runners) { r in
                            let pty = r.drivers.contains("pty")
                            HStack(spacing: Space.s3) {
                                IconTile("server.rack", hue: pty ? GlassInk.green : GlassInk.slate, size: 32)
                                    .overlay(alignment: .topTrailing) { if pty { LiveDot().offset(x: 3, y: -3) } }
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(r.name).coreFont(size: MacTextSize.headline, weight: .semibold)
                                    Text(
                                        pty
                                            ? "Terminals work on this runner."
                                            : "Terminals are off. Turn them on on the machine that runs this runner."
                                    )
                                    .foregroundStyle(GlassInk.secondary)
                                }
                                Spacer()
                                Label(pty ? "On" : "Off", systemImage: pty ? "checkmark.circle.fill" : "minus.circle")
                                    .coreFont(size: MacTextSize.meta, weight: .semibold)
                                    .foregroundStyle(pty ? GlassInk.green : GlassInk.secondary)
                                    .padding(.horizontal, 8).frame(height: 24)
                                    .background((pty ? GlassInk.green : GlassInk.slate).opacity(0.16), in: coreShape(6))
                            }
                            .help("Drivers: \(r.drivers.isEmpty ? "none reported" : r.drivers.joined(separator: ", "))")
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
            .foregroundStyle(GlassInk.primary)
        }
        .task { await model.reload() }
        .accessibilityIdentifier("feature-switches")
    }
}

/// secrets.mode in plain words: whether the Core keeps keys and secrets at all. Off and Test keys are the choices at the
/// top right; Real keys stays locked until the external security review. The track shows where it stands.
private struct SecretsModeCard: View {
    @Bindable var model: RegistryModel
    let setting: SettingItem

    private static let lines = [
        "Your Core keeps no keys or secrets. Nothing can be added until you choose Test keys.",
        "Your Core keeps test keys only. Anything shaped like a real key is refused, to keep you safe while testing.",
        "Your Core keeps real keys.",
    ]

    var body: some View {
        let mode = Int(setting.value)
        let hue = mode == 0 ? GlassInk.orange : GlassInk.blue
        GlassSection(
            "Keys and secrets", sub: "Whether your Core may keep keys and secrets at all.", symbol: "lock.shield.fill",
            hue: GlassInk.blue
        ) {
            HStack(spacing: Space.s2) {
                if model.busy == setting.key { ProgressView().controlSize(.small) }
                CoreSegmented(
                    "Keys and secrets",
                    segments: [
                        CoreSegment(0, "Off", symbol: "lock.fill"), CoreSegment(1, "Test keys", symbol: "testtube.2"),
                    ],
                    selection: Binding(get: { min(mode, 1) }, set: { pick($0) })
                )
                .fixedSize()
                .disabled(model.busy == setting.key)
            }
        } content: {
            StatePanel(
                symbol: mode == 0 ? "lock.fill" : "testtube.2", hue: hue,
                title: mode == 0 ? "Off" : "Test keys",
                line: Self.lines.indices.contains(mode) ? Self.lines[mode] : "A setting this app doesn't know yet.",
                trigger: mode
            ) {
                StepTrack(["Off", "Test keys", "Real keys"], at: min(mode, 2), hue: hue, locked: [2])
                    .help("Real keys open after the external security review (G-SEC).")
            }
            if let e = model.writeError[setting.key] { IssueLine(code: nil, text: e) }
        }
        .help("secrets.mode = \(mode)")
        .animation(.spring(duration: 0.35), value: mode)
    }

    private func pick(_ m: Int) {
        guard m != Int(setting.value) else { return }
        Task {
            await model.set(
                setting, to: Int64(m),
                reason:
                    "Set secrets.mode to \(m). \(m == 0 ? "This refuses every store and lease." : "Throwaway values only.")"
            )
        }
    }
}

/// One on/off feature in plain words: an animated switch tile at the top right (with a "Less safe" mark when turning it
/// on weakens security), and one line saying what it means now.
private struct FlagCard: View {
    @Bindable var model: RegistryModel
    let setting: SettingItem
    let index: Int
    let title: String
    let symbol: String
    let hue: Color
    let sub: String
    let offLine: String
    let onLine: String
    let needs: String?
    var offSymbol = "checkmark.shield.fill"
    var onSymbol = "exclamationmark.shield.fill"
    let reason: (Bool) -> String

    var body: some View {
        let isOn = setting.value >= 1
        GlassSection(title, sub: sub, symbol: symbol, hue: hue, index: index) {
            HStack(spacing: Space.s2) {
                Label("Less safe when on", systemImage: "exclamationmark.triangle.fill")
                    .coreFont(size: MacTextSize.meta, weight: .semibold).foregroundStyle(GlassInk.orangeInk)
                if model.busy == setting.key { ProgressView().controlSize(.small) }
                GlassToggleTile(
                    isOn ? "On" : "Off", symbol: "togglepower", onSymbol: "power",
                    isOn: Binding(
                        get: { isOn }, set: { v in Task { await model.set(setting, to: v ? 1 : 0, reason: reason(v)) } }
                    )
                )
                .disabled(model.busy == setting.key || needs != nil)
                .accessibilityLabel(title)
                .accessibilityIdentifier("switch-\(setting.key)")
            }
        } content: {
            StatePanel(
                symbol: isOn ? onSymbol : offSymbol, hue: isOn ? GlassInk.orange : GlassInk.green,
                title: isOn ? "On · less safe" : "Off · safer", line: isOn ? onLine : offLine, trigger: isOn
            ) { EmptyView() }
            if let needs {
                Label(needs, systemImage: "arrow.turn.right.up").coreFont(size: MacTextSize.meta, weight: .semibold)
                    .foregroundStyle(GlassInk.blueInk)
            }
            if let e = model.writeError[setting.key] { IssueLine(code: nil, text: e) }
        }
        .help(setting.key)
        .animation(.spring(duration: 0.35), value: isOn)
    }
}

/// What a switch means now, as a picture: a large glyph tile in the state's colour that swaps and bounces when the state
/// changes, the state's name and its line, and a light that sweeps across the panel once on every change.
private struct StatePanel<Trailing: View>: View {
    let symbol: String
    let hue: Color
    let title: String
    let line: String
    let trigger: AnyHashable
    @ViewBuilder let trailing: Trailing
    @State private var sweep = false
    @Environment(\.accessibilityReduceMotion) private var reduce

    init(
        symbol: String, hue: Color, title: String, line: String, trigger: some Hashable,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.symbol = symbol
        self.hue = hue
        self.title = title
        self.line = line
        self.trigger = AnyHashable(trigger)
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: Space.s3) {
            Image(systemName: symbol).font(.system(size: 22, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(
                    LinearGradient(colors: [hue, hue.opacity(0.55)], startPoint: .top, endPoint: .bottom),
                    in: coreShape(12)
                )
                .overlay { coreShape(12).strokeBorder(.white.opacity(0.25), lineWidth: 1) }
                .shadow(color: hue.opacity(0.5), radius: 12)
                .contentTransition(.symbolEffect(.replace))
                .coreBounce(trigger)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).coreFont(size: MacTextSize.headline, weight: .bold).foregroundStyle(GlassInk.ink(hue))
                    .contentTransition(.opacity)
                Text(line).foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.s3)
            trailing
        }
        .padding(Space.s3)
        .background(hue.opacity(0.1), in: coreShape(Radius.cardMac))
        .overlay { coreShape(Radius.cardMac).strokeBorder(hue.opacity(0.35), lineWidth: 1) }
        .overlay {
            GeometryReader { g in
                LinearGradient(
                    colors: [.clear, .white.opacity(0.14), .clear], startPoint: .leading, endPoint: .trailing
                )
                .frame(width: g.size.width * 0.35)
                .offset(x: sweep ? g.size.width : -g.size.width * 0.35)
            }
            .clipShape(coreShape(Radius.cardMac))
            .allowsHitTesting(false)
        }
        .animation(Motion.out(Motion.ui), value: hue)
        .onChange(of: trigger) { _, _ in
            guard !reduce else { return }
            sweep = false
            withAnimation(.easeInOut(duration: 0.9)) { sweep = true }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A small green light that breathes: this runner's terminals are live.
private struct LiveDot: View {
    @State private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        coreShape(3).fill(GlassInk.green).frame(width: 9, height: 9)
            .overlay { coreShape(3).strokeBorder(.black.opacity(0.4), lineWidth: 1) }
            .shadow(color: GlassInk.green.opacity(on ? 0.9 : 0.3), radius: on ? 6 : 2)
            .animation(reduce ? nil : .easeInOut(duration: 1.2).repeatForever(), value: on)
            .onAppear { on = true }
    }
}
