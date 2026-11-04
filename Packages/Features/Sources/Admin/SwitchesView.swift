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
                "The Core's gates for secrets and for who may hold admin. Each change needs Touch ID and is audited.",
            state: model.state,
            empty: ("No switches reported", "The registry returned no feature switches.", "switch.2"),
            retry: { Task { await model.reload() } }
        ) {
            VStack(alignment: .leading, spacing: Space.s5) {
                AdminNoticeBanner(notice: admin.host.elevationNotice)
                if let mode = model.item("secrets.mode") { SecretsModeCard(model: model, setting: mode) }
                if let p = model.item("auth.passkey_admin") {
                    AdminSection(
                        title: "Passkey admin",
                        detail: "auth.passkey_admin. Whether web sign-in can hold the admin scope."
                    ) {
                        AdminPanel {
                            FlagRow(
                                model: model, setting: p, title: "Let a passkey hold admin",
                                detail:
                                    "Off by default. While off, pairing or approving a web device with admin is refused (forbidden_scope). Devices that hold it already keep it.",
                                off: "Passkeys read and approve", on: "Passkeys may hold admin",
                                gate: "Weakens security",
                                warn: true,
                                reason: {
                                    $0
                                        ? "Turn on auth.passkey_admin. A stolen passkey session could then hold admin."
                                        : "Turn off auth.passkey_admin."
                                })
                        }
                    }
                }
                if let a = model.item("secrets.provider_accounts") {
                    AdminSection(
                        title: "Provider accounts",
                        detail: "secrets.provider_accounts. The narrow gate for AI provider accounts."
                    ) {
                        AdminPanel {
                            FlagRow(
                                model: model, setting: a, title: "Let provider accounts hold one real key",
                                detail:
                                    "Lets a secret named acct.<provider>.<label> be a real key of that provider's own shape while secrets.mode is 1. It never turns the broker on.",
                                off: "Throwaway values only", on: "Provider keys allowed", gate: "Weakens security",
                                warn: true,
                                reason: {
                                    $0 ? "Turn on secrets.provider_accounts." : "Turn off secrets.provider_accounts."
                                })
                        }
                    }
                }
                if !model.runners.isEmpty {
                    AdminSection(
                        title: "Terminal drivers",
                        detail:
                            "Set when a runner starts, not by the Core. This screen can show them but not change them."
                    ) {
                        AdminPanel {
                            ForEach(model.runners) { r in
                                HStack(alignment: .firstTextBaseline) {
                                    VStack(alignment: .leading, spacing: Space.s1 / 2) {
                                        Text(r.name).font(.system(size: MacTextSize.headline, weight: .semibold))
                                        Text(
                                            r.drivers.isEmpty
                                                ? "No drivers reported" : r.drivers.joined(separator: ", ")
                                        )
                                        .foregroundStyle(palette.text2)
                                    }
                                    Spacer()
                                    if r.drivers.contains("pty") {
                                        StateBadge("pty on", tone: .run, symbol: "checkmark")
                                    } else {
                                        GateTag(text: "Needs the runner flag on the host")
                                    }
                                }
                                .accessibilityElement(children: .combine)
                                AdminFlow(
                                    nodes: [
                                        .init(title: "pty off", sub: "unsupported_command"),
                                        .init(title: "pty on", sub: "terminals open"),
                                    ], current: r.drivers.contains("pty") ? 1 : 0,
                                    edges: [
                                        .init(label: "runner started with the pty flag", met: r.drivers.contains("pty"))
                                    ])
                            }
                        }
                    }
                }
            }
        }
        .task { await model.reload() }
        .accessibilityIdentifier("feature-switches")
    }
}

/// secrets.mode: Off, Throwaway, Real, and what stands between the steps.
private struct SecretsModeCard: View {
    @Bindable var model: RegistryModel
    let setting: SettingItem
    @Environment(\.corePalette) private var palette
    @State private var choice = 0

    private static let names = ["Off", "Throwaway", "Real"]
    private static let notes = [
        "Off. Every store, rotation, lease and redemption is refused (secrets_disabled). Listing and deleting still work.",
        "Throwaway values only. Values shaped like real keys are refused (real_secret_refused).",
        "Real credentials.",
    ]

    var body: some View {
        let mode = Int(setting.value)
        AdminSection(title: "Secrets mode", detail: "secrets.mode. The broker gate for every secret store and lease.") {
            AdminPanel {
                VStack(alignment: .leading, spacing: Space.s2) {
                    Text("Broker mode").font(.system(size: MacTextSize.headline, weight: .semibold))
                    Text(
                        Self.notes.indices.contains(mode) ? Self.notes[mode] : "Mode \(mode) is not one this app knows."
                    )
                    .foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: Space.s3) {
                        CoreSegmented(
                            "Broker mode",
                            segments: [CoreSegment(0, "Off"), CoreSegment(1, "Throwaway")],
                            selection: Binding(get: { min(mode, 1) }, set: { pick($0) })
                        )
                        .frame(maxWidth: Space.s8 * 8)
                        .disabled(model.busy == setting.key)
                        if model.busy == setting.key { AdminBar().frame(width: Space.s8 * 3) }
                    }
                    if let e = model.writeError[setting.key] { IssueLine(code: nil, text: e) }
                }
                AdminFlow(
                    nodes: Self.names.enumerated().map { .init(title: $1, sub: "mode \($0)") }, current: mode,
                    edges: [.init(label: "admin + Touch ID", met: true), .init(label: "G-SEC review", met: false)])
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: Space.s1 / 2) {
                        Text("Mode 2 is closed").font(.system(size: MacTextSize.headline, weight: .semibold))
                        Text("No real credential goes on the host before the external security review (G-SEC).")
                            .foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    GateTag(text: "Closed until G-SEC")
                }
                .accessibilityElement(children: .combine)
            }
        }
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

/// One on/off setting: a switch, what it does, the gate it carries, and its two states with the one that holds.
private struct FlagRow: View {
    @Bindable var model: RegistryModel
    let setting: SettingItem
    let title: String
    let detail: String
    let off: String
    let on: String
    let gate: String
    var warn = false
    let reason: (Bool) -> String
    @Environment(\.corePalette) private var palette

    var body: some View {
        let isOn = setting.value >= 1
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .top, spacing: Space.s3) {
                VStack(alignment: .leading, spacing: Space.s1 / 2) {
                    Text(title).font(.system(size: MacTextSize.headline, weight: .semibold))
                    Text(detail).foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Space.s3)
                GateTag(text: gate, warn: warn)
                AdminSwitch(
                    label: title,
                    on: Binding(
                        get: { isOn }, set: { v in Task { await model.set(setting, to: v ? 1 : 0, reason: reason(v)) } }
                    ),
                    busy: model.busy == setting.key
                )
                .disabled(model.busy == setting.key)
            }
            AdminFlow(
                nodes: [.init(title: "Off", sub: off), .init(title: "On", sub: on)], current: isOn ? 1 : 0,
                edges: [.init(label: "admin + Touch ID", met: true)])
            if model.busy == setting.key { AdminBar().frame(maxWidth: Space.s8 * 5) }
            if let e = model.writeError[setting.key] { IssueLine(code: nil, text: e) }
        }
        .accessibilityElement(children: .contain)
    }
}
