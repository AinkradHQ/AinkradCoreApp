import CoreUI
import SwiftUI

/// Rules as a rulebook: four tiles (All, Always, Never, Prefer, with their share), the rules grouped by kind with where
/// they apply and how sure Brain is, and the chosen rule's panel. New Rule… (⌘N) writes your own. An older Core has no
/// kinds: the rules are one list, and the tiles, the Follow switch and New Rule are not shown.
struct RulesPage: View {
    let brain: BrainModel
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduce
    private var calm: BrainCalmModel { brain.calm }

    var body: some View {
        let s = calm.summary("rules")
        VStack(alignment: .leading, spacing: Space.s4) {
            BrainHead(
                symbol: "checkmark", title: "Rules", count: s?.count, sub: "What Brain follows when it works for you",
                today: s?.today ?? 0
            ) {
                if calm.v101 {
                    Button {
                        BrainSheets.rule(brain)
                    } label: {
                        Label("New Rule…", systemImage: "plus")
                    }
                    .buttonStyle(CoreButtonStyle(.prominent))
                    .keyboardShortcut("n", modifiers: .command).environment(\.coreKeycap, "⌘N")
                    .help("Write a rule in your own words (⌘N)")
                    .accessibilityIdentifier("brain-new-rule")
                }
            }
            if let k = calm.areas?.ruleKinds { tiles(k, total: s?.count ?? 0).coreRise(shown, 0) }
            HStack(spacing: Space.s3) {
                FilterField(placeholder: "Search rules", text: Bindable(calm).filterText) { await calm.refilter() }
                    .frame(maxWidth: Space.s8 * 10)
                if calm.v101 {
                    CoreSelect(
                        nil,
                        selection: Binding(
                            get: { calm.ruleRoom ?? "" },
                            set: { v in
                                calm.ruleRoom = v.isEmpty ? nil : v
                                Task { await calm.refilter() }
                            }),
                        options: [CoreSelectOption("", "All places")]
                            + brain.rooms.filter(\.mounted).map { CoreSelectOption($0.id, $0.name) }
                    )
                    .frame(width: Space.s8 * 6)
                }
                Spacer(minLength: Space.s2)
                Text("Most sure first").coreFont(size: MacTextSize.body).foregroundStyle(GlassInk.secondary)
            }
            HStack(alignment: .top, spacing: Space.s4) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        if calm.records.isEmpty {
                            Text(
                                calm.loading
                                    ? "Reading…" : "No rules here yet. Brain adds them as it learns how you work."
                            )
                            .coreFont(size: MacTextSize.body).foregroundStyle(GlassInk.secondary).padding(Space.s3)
                        }
                        ForEach(sections, id: \.kind) { sec in
                            if let k = sec.kind.flatMap(RuleKind.init(rawValue:)) {
                                header(k).padding(.top, Space.s2)
                            }
                            ForEach(sec.rows) { r in
                                RulebookRow(brain: brain, rule: r, picked: calm.picked == r.id) { calm.picked = r.id }
                            }
                        }
                    }
                    .animation(Motion.calm(Motion.out(Motion.ui), reduce), value: calm.records.map(\.id))
                }
                .frame(maxWidth: .infinity)
                if let r = calm.records.first(where: { $0.id == calm.picked }) {
                    ScrollView { RecordPanel(brain: brain, record: r) }
                        .frame(width: Space.s8 * 11)
                        .transition(.opacity)
                }
            }
            .animation(Motion.calm(Motion.out(Motion.ui), reduce), value: calm.picked)
        }
        .onAppear {
            shown = true
            if calm.picked == nil { calm.picked = calm.records.first?.id }
        }
        .onChange(of: calm.records.map(\.id)) { _, ids in
            if calm.picked.map({ !ids.contains($0) }) ?? true { calm.picked = ids.first }
        }
        .accessibilityIdentifier("brain-rules")
    }

    private struct Section {
        let kind: String?
        let rows: [BrainAreaRecordWire]
    }

    /// Always, Never, Prefer in that order; rules without a kind (an older Core) in one list.
    private var sections: [Section] {
        // The kind filter runs here on the rules already loaded, so a click never waits for the Core (2026-11-23).
        let rs = calm.records.filter { calm.ruleKind == nil || $0.kind == calm.ruleKind }
            .sorted { $0.support > $1.support }
        let kinds = RuleKind.allCases.map(\.rawValue)
        return (kinds.map(Optional.some) + [nil]).compactMap { k -> Section? in
            let rows = rs.filter { k == nil ? !kinds.contains($0.kind ?? "") : $0.kind == k }
            return rows.isEmpty ? nil : Section(kind: k, rows: rows)
        }
    }

    private func count(_ k: RuleKind) -> Int? {
        guard let rk = calm.areas?.ruleKinds else { return nil }
        return switch k {
        case .always: rk.always
        case .never: rk.never
        case .prefer: rk.prefer
        }
    }

    private func header(_ k: RuleKind) -> some View {
        HStack(spacing: Space.s2) {
            KindTile(kind: k, size: Space.s6)
            Text(k.title).coreFont(size: MacTextSize.title, weight: .semibold)
            Text(k.line).coreFont(size: MacTextSize.body).foregroundStyle(GlassInk.secondary)
            Spacer(minLength: Space.s2)
            if let n = count(k) {
                Text(n.formatted()).coreFont(size: MacTextSize.body).foregroundStyle(GlassInk.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, Space.s3)
        .accessibilityAddTraits(.isHeader)
    }

    private func tiles(_ k: BrainAreasWire.RuleKinds, total: Int) -> some View {
        HStack(spacing: Space.s3) {
            KindFilter(title: "All rules", count: total, share: nil, kind: nil, on: calm.ruleKind == nil) { pick(nil) }
            ForEach(RuleKind.allCases, id: \.self) { rk in
                let n = count(rk) ?? 0
                KindFilter(
                    title: rk.title, count: n, share: total > 0 ? Double(n) / Double(total) : 0, kind: rk,
                    on: calm.ruleKind == rk.rawValue
                ) { pick(rk.rawValue) }
            }
        }
    }

    private func pick(_ k: String?) {
        withAnimation(Motion.calm(Motion.out(Motion.ui), reduce)) {
            calm.ruleKind = calm.ruleKind == k ? nil : k
            if let id = calm.picked, let r = calm.records.first(where: { $0.id == id }),
                calm.ruleKind != nil, r.kind != calm.ruleKind
            {
                calm.picked = calm.records.first { $0.kind == calm.ruleKind }?.id
            }
        }
    }
}

/// One of the four tiles over the rulebook: its kind, count and share of all rules.
private struct KindFilter: View {
    let title: String
    let count: Int
    let share: Double?
    let kind: RuleKind?
    let on: Bool
    let pick: () -> Void
    @Environment(\.corePalette) private var palette
    @State private var hover = false

    var body: some View {
        Button(action: pick) {
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(spacing: Space.s3) {
                    if let kind {
                        KindTile(kind: kind, size: Space.s8)
                    } else {
                        BrainTile(symbol: "checkmark", size: Space.s8)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(count.formatted()).font(.system(size: 20, weight: .semibold)).monospacedDigit()
                            .contentTransition(.numericText())
                        Text(title).coreFont(size: MacTextSize.body).foregroundStyle(GlassInk.secondary)
                    }
                    Spacer(minLength: 0)
                }
                // The All tile keeps an empty meter's room, so all four tiles are the same height.
                CoreMeter(share ?? 0, label: "\(title), share of all rules").opacity(share == nil ? 0 : 1)
                    .accessibilityHidden(share == nil)
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                on ? palette.navActive : hover ? GlassInk.wellHover : GlassInk.well, in: coreShape(Radius.cardMac)
            )
            .contentShape(coreShape(Radius.cardMac))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(kind == nil ? "Show every rule" : "Show only \(title) rules")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// A rule in the rulebook: its words, when it was learned and how often seen, where it applies and how sure. Hover shows
/// Edit and Forget.
private struct RulebookRow: View {
    let brain: BrainModel
    let rule: BrainAreaRecordWire
    let picked: Bool
    let pick: () -> Void
    @Environment(\.corePalette) private var palette
    @State private var hover = false

    var body: some View {
        Button(action: pick) {
            HStack(spacing: Space.s3) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(rule.body).coreFont(size: MacTextSize.body, weight: .medium).lineLimit(2)
                        .foregroundStyle(rule.following == false ? GlassInk.secondary : GlassInk.primary)
                    meta.coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                }
                Spacer(minLength: Space.s2)
                // Always laid out, shown on hover, so the row never shifts.
                HStack(spacing: Space.s1) {
                    if brain.calm.v101 {
                        CoreIconButton(symbol: "pencil", label: "Edit rule") { BrainSheets.rule(brain, editing: rule) }
                            .help("Edit this rule")
                    }
                    CoreIconButton(symbol: "trash", label: "Forget rule") { brain.forget(rule) }
                        .help("Forget this rule (⌘⌫ when it is open). Undo brings it back.")
                }
                .opacity(hover ? 1 : 0).allowsHitTesting(hover)
                if rule.everywhere == true {
                    PlaceChip(name: "", everywhere: true)
                } else {
                    ForEach((rule.rooms?.map(\.name) ?? [rule.roomName]).prefix(2), id: \.self) { PlaceChip(name: $0) }
                }
                SureBars(support: rule.support)
            }
            .padding(.horizontal, Space.s3).padding(.vertical, Space.s2 + 2)
            .background(
                picked ? palette.navActive : hover ? palette.rowHover : .clear, in: coreShape(Radius.control)
            )
            .contentShape(coreShape(Radius.control))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .accessibilityAddTraits(picked ? .isSelected : [])
        .accessibilityIdentifier("brain-rule-\(rule.id)")
    }

    private var meta: Text {
        let d = SyncWords.date(rule.createdAt)
        let new = d.map { Calendar.current.isDateInToday($0) } ?? false
        let seen = " · seen in \(BrainWords.plural(rule.support, "session", "sessions"))"
        let off = rule.following == false ? " · not followed" : ""
        if new { return Text("New today").fontWeight(.semibold).foregroundColor(palette.success) + Text(seen + off) }
        return Text("Learned \(d.map { SyncWords.agoInLine($0) } ?? "–")" + seen + off)
    }
}
