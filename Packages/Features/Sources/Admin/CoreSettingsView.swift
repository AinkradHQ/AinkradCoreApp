import CoreUI
import SwiftUI

/// Settings, Core, Core settings: every limit the Core reports, with its bounds, where the value came from and its history.
struct CoreSettingsSection: View {
    let admin: AdminModel
    @Environment(\.corePalette) private var palette

    var body: some View {
        let model = admin.registry!
        AdminScreen(
            admin: admin, what: "Settings",
            intro:
                "Limits and thresholds the Core enforces. A value outside the limits is refused, never clamped. Changing one needs Touch ID.",
            state: model.state, empty: ("No settings reported", "The registry returned nothing for this Core.", "tray"),
            retry: { Task { await model.reload() } }
        ) {
            VStack(alignment: .leading, spacing: Space.s5) {
                AdminNoticeBanner(notice: admin.host.elevationNotice)
                ForEach(model.groups, id: \.name) { group in
                    AdminSection(
                        title: group.name,
                        detail:
                            "settings/server. Values outside the limits are refused with out_of_bounds, never clamped."
                    ) {
                        AdminPanel(spacing: Space.s6) {
                            ForEach(group.items) { s in SettingRow(model: model, setting: s) }
                        }
                    }
                }
            }
        }
        .task { await model.reload() }
        .accessibilityIdentifier("core-settings")
    }
}

private struct SettingRow: View {
    @Bindable var model: RegistryModel
    let setting: SettingItem
    @Environment(\.corePalette) private var palette

    private var editing: Bool { model.editing == setting.key }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .top, spacing: Space.s3) {
                VStack(alignment: .leading, spacing: Space.s1) {
                    HStack(spacing: Space.s2) {
                        Text(setting.name).font(.system(size: MacTextSize.body, weight: .semibold, design: .monospaced))
                        MetaChip(text: setting.isOverride ? "source: override" : "source: default")
                    }
                    Text(setting.detail).foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Space.s3)
                HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                    HStack(alignment: .firstTextBaseline, spacing: Space.s1) {
                        Text(AdminWords.number(setting.value)).font(
                            .system(size: MacTextSize.body, weight: .semibold, design: .monospaced))
                        Text(setting.unitLabel).foregroundStyle(palette.text2)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(setting.key), \(setting.value) \(setting.unit)")
                    AdminLink(title: "Edit", help: "Change \(setting.key)") { model.beginEdit(setting) }
                        .accessibilityLabel("Edit \(setting.key)")
                    AdminLink(
                        title: model.openHistory == setting.key ? "Hide history" : "History",
                        help: "Who changed \(setting.key), and when"
                    ) {
                        Task { await model.toggleHistory(setting.key) }
                    }
                    .accessibilityLabel("History of \(setting.key)")
                    if setting.isOverride {
                        AdminLink(title: "Reset", danger: true, help: "Put \(setting.key) back to its default") {
                            Task { await model.reset(setting) }
                        }
                        .accessibilityLabel("Reset \(setting.key)")
                    }
                }
            }
            RangeBar(setting: setting, ghost: editing ? model.draftValue() : nil)
            if let e = model.writeError[setting.key] { IssueLine(code: nil, text: e) }
            if editing { editor }
            if model.openHistory == setting.key { HistoryTimeline(setting: setting, load: model.history[setting.key]) }
        }
        .padding(.vertical, Space.s1)
        .contextMenu {
            Button("Edit value…") { model.beginEdit(setting) }
            Button(model.openHistory == setting.key ? "Hide history" : "Show history") {
                Task { await model.toggleHistory(setting.key) }
            }
            if setting.isOverride { Button("Reset to default") { Task { await model.reset(setting) } } }
            Button("Copy key") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(setting.key, forType: .string)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .bottom, spacing: Space.s2) {
                CoreTextField(
                    "New value for \(setting.key)", placeholder: String(setting.value), text: $model.draft,
                    error: nil, mono: false, suffix: setting.unitLabel.isEmpty ? nil : setting.unitLabel,
                    autofocus: true, onSubmit: { Task { await model.saveEdit(setting) } }
                )
                .frame(maxWidth: Space.s8 * 7)
                Button("Save") { Task { await model.saveEdit(setting) } }
                    .buttonStyle(CoreButtonStyle(.prominent, busy: model.busy == setting.key))
                Button("Cancel") { model.cancelEdit() }.buttonStyle(.coreSecondary)
                GateTag(text: "Needs Touch ID")
            }
            if let issue = model.issue { IssueLine(code: issue.code, text: issue.message) }
        }
        .onKeyPress(.escape) {
            model.cancelEdit()
            return .handled
        }
    }
}

/// Where the value sits between the bounds: a filled track, a marker at the value, a tick and its label at the default and,
/// while typing, a ghost marker for the draft (red with the words when it would be refused).
struct RangeBar: View {
    let setting: SettingItem
    var ghost: Int64?
    @Environment(\.corePalette) private var palette

    var body: some View {
        let refused = ghost.map { $0 < setting.min || $0 > setting.max } ?? false
        VStack(spacing: Space.s1) {
            GeometryReader { geo in
                let w = geo.size.width
                let labelW = Space.s8 * 3
                let dx = w * setting.position(setting.defaultValue)
                ZStack(alignment: .topLeading) {
                    Text("default \(AdminWords.number(setting.defaultValue))")
                        .font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2).lineLimit(1)
                        .frame(width: labelW)
                        .offset(x: min(max(dx - labelW / 2, 0), max(w - labelW, 0)))  // grid: ok label over its tick
                    ZStack(alignment: .leading) {
                        coreShape(Space.s1 / 2).fill(palette.track).frame(height: Space.s1)
                        coreShape(Space.s1 / 2).fill(palette.primary)
                            .frame(width: max(w * setting.position(setting.value), Space.s1), height: Space.s1)
                        // grid: ok tick
                        coreShape(1).fill(palette.text2).frame(width: 2, height: Space.s3).offset(x: dx - 1)
                        coreShape(Space.s1 / 2).fill(palette.primary).frame(width: Space.s2, height: Space.s4)
                            // grid: ok marker
                            .offset(x: min(max(w * setting.position(setting.value) - Space.s1, 0), w - Space.s2))
                        if let ghost {
                            coreShape(Space.s1 / 2).fill(refused ? palette.tone(.fail).ink : palette.text)
                                .frame(width: Space.s1, height: Space.s4)
                                // grid: ok ghost
                                .offset(x: min(max(w * setting.position(ghost) - Space.s1 / 2, 0), w - Space.s1))
                        }
                    }
                    .frame(height: Space.s4).offset(y: Space.s4)  // grid: ok track under its label
                }
            }
            .frame(height: Space.s8 - Space.s1)
            HStack {
                Text("min \(AdminWords.number(setting.min))")
                Spacer()
                if let ghost, refused {
                    Label(
                        "\(ghost) would be refused: \(ghost < setting.min ? "below the minimum" : "above the maximum")",
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(palette.tone(.fail).ink)
                }
                Spacer()
                Text("max \(AdminWords.number(setting.max))")
            }
            .font(.system(size: MacTextSize.meta, design: .monospaced)).foregroundStyle(palette.text2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(setting.key): \(setting.value) \(setting.unit), allowed \(setting.min) to \(setting.max), default \(setting.defaultValue)"
        )
    }
}

/// Who changed a setting, newest first. The first entry is what holds now.
private struct HistoryTimeline: View {
    let setting: SettingItem
    let load: HistoryLoad?
    @Environment(\.corePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            switch load {
            case .none, .loading?: AdminBar().frame(maxWidth: Space.s8 * 5)
            case .failed(let m)?: IssueLine(code: nil, text: m)
            case .ready(let list)?:
                if list.isEmpty {
                    row(
                        when: "Never changed", who: "", change: "default \(AdminWords.number(setting.defaultValue))",
                        current: true)
                }
                ForEach(Array(list.enumerated()), id: \.element.id) { i, c in
                    row(
                        when: AdminWords.when(c.at), who: c.actor.label, change: SettingChangeWords.text(c),
                        current: i == 0)
                }
            }
        }
        .padding(.top, Space.s1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("History of \(setting.key)")
    }

    private func row(when: String, who: String, change: String, current: Bool) -> some View {
        HStack(spacing: Space.s3) {
            Text(when).font(.system(size: MacTextSize.meta, design: .monospaced)).foregroundStyle(palette.text2)
                .frame(width: Space.s8 * 4, alignment: .leading)
            Text(who).frame(width: Space.s8 * 4, alignment: .leading).lineLimit(1)
            Text(change).font(.system(size: MacTextSize.body, design: .monospaced))
            if current { StateBadge("Current", tone: .done, symbol: "checkmark") }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.s3).frame(minHeight: MacSize.controlMd)
        .background(palette.uDim, in: coreShape(Radius.control))
        .accessibilityElement(children: .combine)
    }
}
