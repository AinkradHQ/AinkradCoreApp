import CoreUI
import SwiftUI

/// Settings, Core, Feature switches: the settings that gate a feature, each with the steps between its states.
struct SwitchesSection: View {
    let admin: AdminModel
    @Environment(\.corePalette) private var palette

    var body: some View {
        let model = admin.registry!
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
                            $0 ? "Turn on secrets.provider_accounts." : "Turn off secrets.provider_accounts."
                        })
                }
                if let p = model.item("auth.passkey_admin") {
                    FlagCard(
                        model: model, setting: p, index: 2, title: "Admin from a browser", symbol: "globe",
                        hue: GlassInk.violet,
                        sub: "Let a device that signs in with a passkey in a web browser become an admin.",
                        offLine: "Browser devices can read and approve, but not change your Core. Safer.",
                        onLine:
                            "Browser devices can become admin. Someone who steals that browser could change your Core.",
                        needs: nil,
                        reason: {
                            $0
                                ? "Turn on auth.passkey_admin. A stolen passkey session could then hold admin."
                                : "Turn off auth.passkey_admin."
                        })
                }
                if !model.runners.isEmpty {
                    GlassSection(
                        "Terminals on your runners",
                        sub: "Set on each runner when it starts. Shown here, changed there.",
                        symbol: "terminal.fill", hue: GlassInk.green, index: 3
                    ) {
                        ForEach(model.runners) { r in
                            let pty = r.drivers.contains("pty")
                            HStack(spacing: Space.s3) {
                                IconTile("server.rack", hue: pty ? GlassInk.green : GlassInk.slate, size: 32)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(r.name).font(.system(size: MacTextSize.headline, weight: .semibold))
                                    Text(
                                        pty
                                            ? "Terminals work on this runner."
                                            : "Terminals are off: this runner was started without terminal support."
                                    )
                                    .foregroundStyle(GlassInk.secondary)
                                }
                                Spacer()
                                Label(pty ? "On" : "Off", systemImage: pty ? "checkmark.circle.fill" : "minus.circle")
                                    .font(.system(size: MacTextSize.meta, weight: .semibold))
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
            HStack(spacing: Space.s3) {
                Image(systemName: mode == 0 ? "lock.fill" : "testtube.2").foregroundStyle(hue)
                    .contentTransition(.symbolEffect(.replace))
                Text(Self.lines.indices.contains(mode) ? Self.lines[mode] : "A setting this app doesn't know yet.")
                    .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Space.s3)
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
    let reason: (Bool) -> String

    var body: some View {
        let isOn = setting.value >= 1
        GlassSection(title, sub: sub, symbol: symbol, hue: hue, index: index) {
            HStack(spacing: Space.s2) {
                Label("Less safe when on", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: MacTextSize.meta, weight: .semibold)).foregroundStyle(GlassInk.orange)
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
            HStack(spacing: Space.s2) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "minus.circle")
                    .foregroundStyle(isOn ? GlassInk.orange : GlassInk.secondary)
                    .contentTransition(.symbolEffect(.replace))
                Text(isOn ? onLine : offLine).foregroundStyle(GlassInk.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let needs {
                Label(needs, systemImage: "arrow.turn.right.up").font(
                    .system(size: MacTextSize.meta, weight: .semibold)
                )
                .foregroundStyle(GlassInk.blue)
            }
            if let e = model.writeError[setting.key] { IssueLine(code: nil, text: e) }
        }
        .help(setting.key)
        .animation(.spring(duration: 0.35), value: isOn)
    }
}
