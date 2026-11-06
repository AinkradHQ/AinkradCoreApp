import CoreUI
import SwiftUI

/// Settings, Core, Core settings: every limit the Core reports, in plain words, grouped by what it is about. One row is the
/// cursor (↑ ↓); ↩ changes it, H shows who changed it, ⌫ puts it back to its default, esc closes.
struct CoreSettingsSection: View {
    let admin: AdminModel
    @FocusState private var listFocus: Bool

    var body: some View {
        let model = admin.registry!
        AdminScreen(
            admin: admin, what: "Settings",
            intro:
                "The limits your Core keeps to. Pick one and press ↩ to change it. Each change asks for Touch ID and can be undone.",
            state: model.state, empty: ("No settings reported", "Your Core returned no settings.", "tray"),
            retry: { Task { await model.reload() } }
        ) {
            ScrollViewReader { proxy in
                VStack(alignment: .leading, spacing: Space.s4) {
                    AdminNoticeBanner(notice: admin.host.elevationNotice)
                    ForEach(Array(sections(model).enumerated()), id: \.element.0.id) { i, pair in
                        let (group, items) = pair
                        GlassSection(group.title, sub: group.sub, symbol: group.symbol, hue: group.hue, index: i) {
                            let changed = items.filter(\.isOverride).count
                            SettingsChip(
                                text: changed == 0 ? "All default" : "\(changed) changed",
                                symbol: changed == 0 ? "checkmark" : "slider.horizontal.3",
                                hue: changed == 0 ? GlassInk.slate : group.hue)
                        } content: {
                            VStack(spacing: Space.s2) {
                                ForEach(items) { s in
                                    LimitRow(model: model, setting: s, hue: group.hue) {
                                        model.cursor = s.key
                                        listFocus = true
                                    }
                                    .id(s.key)
                                }
                            }
                        }
                    }
                }
                .onChange(of: model.cursor) { _, key in
                    guard let key else { return }
                    withAnimation(Motion.out(Motion.ui)) { proxy.scrollTo(key, anchor: .center) }
                }
            }
            .focusable().focused($listFocus).focusEffectDisabled()
            .onKeyPress(phases: .down) { press in keys(press, model) }
            .onChange(of: model.editing) { _, now in if now == nil { listFocus = true } }
        }
        .task {
            await model.reload()
            if model.cursor == nil { model.cursor = sections(model).first?.1.first?.key }
            listFocus = true
        }
        .accessibilityIdentifier("core-settings")
    }

    private func sections(_ model: RegistryModel) -> [(SettingWords.Group, [SettingItem])] {
        var order: [String] = SettingWords.groups.map(\.id)
        var by: [String: (SettingWords.Group, [SettingItem])] = [:]
        for s in model.limits {
            let g = SettingWords.group(s)
            if !order.contains(g.id) { order.append(g.id) }
            by[g.id, default: (g, [])].1.append(s)
        }
        return order.compactMap { by[$0] }
    }

    private func keys(_ press: KeyPress, _ model: RegistryModel) -> KeyPress.Result {
        guard model.editing == nil else { return .ignored }
        let list = sections(model).flatMap(\.1)
        let at = list.firstIndex { $0.key == model.cursor } ?? 0
        func go(_ i: Int) -> KeyPress.Result {
            guard list.indices.contains(i) else { return .handled }
            withAnimation(Motion.out(Motion.ui)) { model.cursor = list[i].key }
            return .handled
        }
        guard let s = list.indices.contains(at) ? list[at] : nil else { return .ignored }
        switch press.key {
        case .downArrow: return go(at + 1)
        case .upArrow: return go(at - 1)
        case .home: return go(0)
        case .end: return go(list.count - 1)
        case .return, .space:
            model.beginEdit(s)
            return .handled
        case .escape:
            if model.openHistory != nil { Task { await model.toggleHistory(model.openHistory!) } }
            return .handled
        case .delete, .deleteForward:
            if s.isOverride { Task { await model.reset(s) } }
            return .handled
        default:
            if press.characters.lowercased() == "h" {
                Task { await model.toggleHistory(s.key) }
                return .handled
            }
            return .ignored
        }
    }
}

/// One limit: its plain name and what it does, the value as people say it, and where it sits between the limits. The
/// cursor row is lit and shows its actions: History, Reset (when changed) and Change.
private struct LimitRow: View {
    @Bindable var model: RegistryModel
    let setting: SettingItem
    let hue: Color
    let pick: () -> Void
    @State private var hovering = false

    private var editing: Bool { model.editing == setting.key }
    private var selected: Bool { model.cursor == setting.key }
    private var showsActions: Bool { (selected || hovering) && !editing }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .top, spacing: Space.s3) {
                VStack(alignment: .leading, spacing: Space.s1 / 2) {
                    HStack(spacing: Space.s2) {
                        Text(SettingWords.title(setting)).font(.system(size: MacTextSize.headline, weight: .semibold))
                        if setting.isOverride {
                            SettingsChip(text: "Changed", symbol: "pencil", hue: hue)
                        }
                        if SettingWords.needsRestart(setting) {
                            SettingsChip(text: "After a restart", symbol: "arrow.clockwise", hue: GlassInk.orange)
                                .help("Your Core reads this only when it starts.")
                        }
                    }
                    Text(SettingWords.line(setting)).foregroundStyle(GlassInk.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Space.s3)
                // Always laid out, only faded: showing them never changes the row's size under the pointer.
                actions.opacity(showsActions ? 1 : 0).allowsHitTesting(showsActions)
                Text(SettingWords.value(setting, setting.value))
                    .font(.system(size: MacTextSize.large, weight: .semibold, design: .rounded))
                    .foregroundStyle(selected ? hue : GlassInk.primary)
                    .contentTransition(.numericText())
            }
            RangeBar(setting: setting, hue: hue, ghost: editing ? model.draftValue() : nil)
            if let e = model.writeError[setting.key] { IssueLine(code: nil, text: e) }
            if editing {
                LimitEditor(model: model, setting: setting, hue: hue).transition(.opacity)
            }
            if model.openHistory == setting.key {
                HistoryTimeline(setting: setting, hue: hue, load: model.history[setting.key]).transition(.opacity)
            }
        }
        .padding(Space.s3)
        .background(selected ? hue.opacity(0.14) : hovering ? GlassInk.wellHover : GlassInk.well, in: rowShape)
        .overlay { rowShape.strokeBorder(GlassInk.wellEdge, lineWidth: 1) }
        .contentShape(rowShape)
        .onTapGesture(perform: pick)
        .onHover { hovering = $0 }
        .animation(Motion.out(Motion.ui), value: showsActions)
        .animation(Motion.out(Motion.ui), value: selected)
        .animation(Motion.out(Motion.ui), value: model.openHistory)
        .animation(Motion.out(Motion.move), value: setting.value)
        .help("\(setting.key): \(setting.detail)")
        .contextMenu {
            Button("Change…") { model.beginEdit(setting) }
            Button(model.openHistory == setting.key ? "Hide history" : "Show history") {
                Task { await model.toggleHistory(setting.key) }
            }
            if setting.isOverride { Button("Back to default") { Task { await model.reset(setting) } } }
            Button("Copy setting name") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(setting.key, forType: .string)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(SettingWords.title(setting)), \(SettingWords.value(setting, setting.value))")
    }

    private var rowShape: some InsettableShape { coreShape(Radius.cardMac) }

    private var actions: some View {
        HStack(spacing: Space.s2) {
            AppActionTile(
                title: model.openHistory == setting.key ? "Hide history" : "History", symbol: "clock.arrow.circlepath",
                key: selected ? "H" : "", hue: GlassInk.slate
            ) { Task { await model.toggleHistory(setting.key) } }
            if setting.isOverride {
                AppActionTile(
                    title: "Back to \(SettingWords.value(setting, setting.defaultValue))",
                    symbol: "arrow.uturn.backward",
                    key: selected ? "⌫" : "", hue: GlassInk.slate
                ) { Task { await model.reset(setting) } }
            }
            AppActionTile(
                title: "Change", symbol: "slider.horizontal.3", key: selected ? "↩" : "", hue: hue, prominent: true
            ) {
                pick()
                model.beginEdit(setting)
            }
        }
    }
}

/// The new value, typed in the Core's unit, read back in plain words as you type. Cancel left (esc), Save right (↩).
private struct LimitEditor: View {
    @Bindable var model: RegistryModel
    let setting: SettingItem
    let hue: Color

    var body: some View {
        let typed = model.draftValue()
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .center, spacing: Space.s3) {
                AppActionTile(title: "Cancel", symbol: "xmark", key: "esc", hue: GlassInk.slate) { model.cancelEdit() }
                CoreTextField(
                    "New value", placeholder: String(setting.value), text: $model.draft, error: nil, mono: true,
                    suffix: unitWord, autofocus: true, onSubmit: { Task { await model.saveEdit(setting) } }
                )
                .frame(maxWidth: Space.s8 * 6)
                if let typed {
                    Label(SettingWords.value(setting, typed), systemImage: "equal")
                        .font(.system(size: MacTextSize.headline, weight: .semibold, design: .rounded))
                        .foregroundStyle(hue).contentTransition(.numericText())
                }
                Spacer(minLength: Space.s3)
                Label("Asks for Touch ID", systemImage: "touchid").font(.system(size: MacTextSize.meta))
                    .foregroundStyle(GlassInk.secondary)
                AppActionTile(title: "Save", symbol: "checkmark", key: "↩", hue: hue, prominent: true) {
                    Task { await model.saveEdit(setting) }
                }
                .opacity(model.busy == setting.key ? 0.5 : 1)
            }
            if let issue = model.issue { IssueLine(code: nil, text: issue.message) }
        }
        .padding(Space.s3)
        .background(hue.opacity(0.08), in: coreShape(Radius.control))
        .animation(Motion.out(Motion.ui), value: typed)
        .onKeyPress(.escape) {
            model.cancelEdit()
            return .handled
        }
    }

    /// The unit the number is typed in.
    private var unitWord: String? {
        switch setting.unit {
        case "seconds": "seconds"
        case "bytes": "bytes"
        case "percent": "%"
        case "per_minute": "a minute"
        default: setting.key == "alarm.cert_min_days" ? "days" : nil
        }
    }
}

/// A small tinted word with a glyph.
struct SettingsChip: View {
    let text: String
    let symbol: String
    let hue: Color
    var body: some View {
        Label(text, systemImage: symbol).font(.system(size: MacTextSize.meta, weight: .semibold))
            .foregroundStyle(hue == GlassInk.slate ? GlassInk.secondary : hue)
            .padding(.horizontal, Space.s2).frame(height: MacSize.controlSm)
            .background(hue.opacity(0.16), in: coreShape(Radius.chip))
    }
}

/// Where the value sits between the limits: a fill up to the value, a tick at the default and, while typing, a
/// ghost marker for the draft (red with the words when it would be refused).
struct RangeBar: View {
    let setting: SettingItem
    var hue: Color = GlassInk.blue
    var ghost: Int64?

    var body: some View {
        let refused = ghost.map { $0 < setting.min || $0 > setting.max } ?? false
        VStack(spacing: Space.s1) {
            GeometryReader { geo in
                let w = geo.size.width
                let x = w * setting.position(setting.value)
                let dx = w * setting.position(setting.defaultValue)
                ZStack(alignment: .leading) {
                    coreShape(3).fill(GlassInk.track.opacity(0.6)).frame(height: 6)
                    coreShape(3)
                        .fill(
                            LinearGradient(colors: [hue.opacity(0.5), hue], startPoint: .leading, endPoint: .trailing)
                        )
                        .frame(width: max(x, 6), height: 6)
                    coreShape(1).fill(GlassInk.secondary).frame(width: 2, height: 12)
                        .offset(x: dx - 1)  // grid: ok tick
                    coreShape(4).fill(.white).frame(width: 8, height: 18)
                        .overlay { coreShape(4).strokeBorder(hue, lineWidth: 2) }
                        .offset(x: min(max(x - 4, 0), w - 8))  // grid: ok marker
                    if let ghost {
                        coreShape(3).fill(refused ? GlassInk.red : GlassInk.primary.opacity(0.8))
                            .frame(width: 6, height: 18)
                            .offset(x: min(max(w * setting.position(ghost) - 3, 0), w - 6))  // grid: ok ghost
                    }
                }
                .frame(height: 18)
            }
            .frame(height: 18)
            HStack {
                Text(SettingWords.value(setting, setting.min))
                Spacer()
                if let ghost, refused {
                    Label(
                        "\(SettingWords.value(setting, ghost)) is \(ghost < setting.min ? "below the lowest" : "above the highest") allowed",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(GlassInk.red)
                } else {
                    Text("Default \(SettingWords.value(setting, setting.defaultValue))")
                }
                Spacer()
                Text(SettingWords.value(setting, setting.max))
            }
            .font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(SettingWords.value(setting, setting.value)), allowed \(SettingWords.value(setting, setting.min)) to \(SettingWords.value(setting, setting.max)), default \(SettingWords.value(setting, setting.defaultValue))"
        )
    }
}

/// Who changed a setting, newest first, as a timeline. The first entry is what holds now.
private struct HistoryTimeline: View {
    let setting: SettingItem
    let hue: Color
    let load: HistoryLoad?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch load {
            case .none, .loading?: AdminBar().frame(maxWidth: Space.s8 * 5)
            case .failed(let m)?: IssueLine(code: nil, text: m)
            case .ready(let list)?:
                if list.isEmpty {
                    row(
                        when: "Never changed", who: "", change: "Default \(word(setting.defaultValue))", current: true,
                        last: true)
                }
                ForEach(Array(list.enumerated()), id: \.element.id) { i, c in
                    row(
                        when: AdminWords.when(c.at), who: c.actor.label, change: text(c), current: i == 0,
                        last: i == list.count - 1)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("History of \(SettingWords.title(setting))")
    }

    private func word(_ n: Int64) -> String { SettingWords.value(setting, n) }

    private func text(_ c: SettingChangeItem) -> String {
        let old = c.old.map(word) ?? "Default"
        guard let new = c.new else { return "\(old) → back to default" }
        return "\(old) → \(word(new))"
    }

    private func row(when: String, who: String, change: String, current: Bool, last: Bool) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            VStack(spacing: 0) {
                coreShape(3).fill(current ? hue : GlassInk.track).frame(width: 10, height: 10)
                    .padding(.top, Space.s1)
                if !last { Rectangle().fill(GlassInk.track).frame(width: 2).frame(maxHeight: .infinity) }
            }
            .frame(width: 10)
            VStack(alignment: .leading, spacing: Space.s1 / 2) {
                HStack(spacing: Space.s2) {
                    Text(change).font(.system(size: MacTextSize.body, weight: .semibold))
                    if current { SettingsChip(text: "Now", symbol: "checkmark", hue: GlassInk.green) }
                }
                Text(who.isEmpty ? when : "\(when) · \(who)").font(.system(size: MacTextSize.meta))
                    .foregroundStyle(GlassInk.secondary)
            }
            .padding(.bottom, Space.s3)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
