import CoreUI
import SwiftUI

/// Allow and Deny on a waiting item, from the actions the item carries (the primary one is blue).
struct WActions: View {
    let item: BellItem
    var body: some View {
        HStack(spacing: Space.s2) {
            ForEach(item.actions.sorted { $0.primary && !$1.primary }) { a in
                Button(a.label == "Approve" ? "Allow" : a.label) { a.run() }
                    .buttonStyle(CoreButtonStyle(a.primary ? .prominent : .secondary, size: .small))
            }
        }
    }
}

struct CoreBody: View {
    @Bindable var shell: ShellModel
    let size: WidgetSize
    @Environment(\.accessibilityReduceMotion) private var reduce

    private var state: (word: String, tone: Tone, symbol: String) {
        switch shell.coreLink {
        case .live: ("OK", .done, "checkmark")
        case .connecting, .reconnecting: ("Reconnecting", .warn, "arrow.triangle.2.circlepath")
        case .offline: ("Offline", .fail, "exclamationmark.triangle")
        case .none: ("Not connected", .queue, "minus")
        }
    }

    var body: some View {
        let s = state
        let alarms = shell.bell.items.filter { $0.kind == .alarm }.count
        let h = shell.home
        let ratio = h.machines.isEmpty ? 0 : Double(h.machinesOnline) / Double(h.machines.count)
        VStack(alignment: .leading, spacing: Space.s2) {
            switch size {
            case .s:
                WHead("heart.text.square", "Core")
                HStack(spacing: Space.s2) {
                    Image(systemName: s.symbol).coreFont(size: 26, weight: .semibold)
                        .foregroundStyle(s.tone == .done ? GlassInk.green : GlassInk.amber)
                        .contentTransition(.symbolEffect(.replace)).accessibilityHidden(true)
                    Text(s.word).coreFont(size: 28, weight: .bold).foregroundStyle(GlassInk.primary)
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
                Spacer(minLength: 0)
                WCaption(h.health.map { "Up \($0.uptime)" } ?? (alarms == 0 ? "No alarms" : "\(alarms) alarms"))
            case .m:
                WHead("heart.text.square", "Core health") { StateBadge(s.word, tone: s.tone, symbol: s.symbol) }
                HStack(alignment: .top, spacing: Space.s5) {
                    if let c = h.health?.certificate { stat("Certificate", c) }
                    if let b = h.health?.backupAge(now: Date()) { stat("Backup", b) }
                    stat("Runners", "\(h.machinesOnline) of \(h.machines.count)")
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
                WCaption(h.health.map { "Core \($0.version) · up \($0.uptime)" } ?? h.coreName)
            case .w:
                WHead("heart.text.square", "Core health") { StateBadge(s.word, tone: s.tone, symbol: s.symbol) }
                WStats(items: [
                    .init(id: "Runners up", value: "\(h.machinesOnline) of \(h.machines.count)", bar: ratio),
                    .init(
                        id: "Alarms", value: alarms == 0 ? "None" : "\(alarms)", warn: alarms > 0,
                        bar: min(Double(alarms) / 5, 1)),
                    .init(
                        id: "Certificate", value: h.health?.certificate ?? "n/a",
                        warn: h.health?.certificateLow ?? false,
                        bar: h.health?.certificateShare),
                    .init(id: "Backup", value: h.health?.backupAge(now: Date()) ?? "None yet"),
                ])
            case .l:
                WHead("heart.text.square", "Core health") { StateBadge(s.word, tone: s.tone, symbol: s.symbol) }
                VStack(alignment: .leading, spacing: 0) {
                    Text(s.tone == .done ? "Healthy" : s.word).coreFont(size: 34, weight: .bold)
                        .foregroundStyle(GlassInk.primary)
                    WCaption(h.health.map { "\(h.coreName) · version \($0.version) · up \($0.uptime)" } ?? h.coreName)
                }
                barsA(alarms: alarms, ratio: ratio, h: h)
                barsB(h: h)
                Spacer(minLength: 0)
            }
        }
        .animation(Motion.calm(Motion.out(Motion.ui), reduce), value: shell.coreLink)
    }

    @ViewBuilder private func barsA(alarms: Int, ratio: Double, h: HomeSnapshot) -> some View {
        WBarRow(
            label: "Runners online", value: "\(h.machinesOnline) of \(h.machines.count)", fill: ratio)
        WBarRow(
            label: "Alarms", value: alarms == 0 ? "None" : "\(alarms)", fill: min(Double(alarms) / 5, 1),
            low: alarms > 0)
    }

    @ViewBuilder private func barsB(h: HomeSnapshot) -> some View {
        if let c = h.health?.certificate, let health = h.health {
            WBarRow(
                label: "Certificate", value: c + (health.certDaysLeft ?? 0 > 0 ? " left" : ""),
                fill: health.certificateShare, low: health.certificateLow)
        }
        if let b = h.health?.backup(now: Date()), let at = h.health?.lastBackupAt {
            WBarRow(
                label: "Backup", value: b, fill: max(0, 1 - Date().timeIntervalSince(at) / (2 * 86_400)))
        }
    }

    private func stat(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            WCaption(k)
            Text(v).coreFont(size: 20, weight: .bold).foregroundStyle(GlassInk.primary).lineLimit(1)
                .minimumScaleFactor(0.6).contentTransition(.numericText())
        }
    }
}
