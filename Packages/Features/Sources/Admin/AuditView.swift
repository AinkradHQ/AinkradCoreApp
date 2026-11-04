import CoreUI
import SwiftUI

/// Settings, Security, Audit: filter by kind, target and actor; page back through the log; select a row for its details.
struct AuditSection: View {
    let admin: AdminModel
    @Environment(\.corePalette) private var palette

    var body: some View {
        let model = admin.audit!
        AdminScreen(
            admin: admin, what: "The audit log",
            intro:
                "Who did what, where and when, newest first. Rows are content free: never terminal bytes or secret values.",
            state: model.state,
            empty: (
                "Nothing recorded yet", "Rows appear as devices pair, settings change and secrets are used.", "doc.text"
            ),
            retry: { Task { await model.reload() } }
        ) {
            VStack(alignment: .leading, spacing: Space.s4) {
                Filters(model: model)
                if let d = model.density() { Density(cells: d.cells, from: d.from, to: d.to) }
                if model.items.isEmpty {
                    StateCard(
                        symbol: "magnifyingglass", title: "No rows match",
                        text: "No audit rows match these filters. Only kind, target and actor can be filtered."
                    ) { Button("Clear filters") { model.clearFilters() }.buttonStyle(.coreSecondary) }
                } else {
                    HStack(alignment: .top, spacing: Space.s3) {
                        AuditList(model: model)
                        AuditDetail(item: model.selection).frame(width: Space.s8 * 8)
                    }
                }
                Text(
                    "Export is available on the host only. Exporting and verifying the audit log are host commands, not Core API routes."
                )
                .font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
            }
        }
        .task { await model.reload() }
        .accessibilityIdentifier("audit")
    }
}

private struct Filters: View {
    @Bindable var model: AuditModel
    var body: some View {
        HStack(alignment: .bottom, spacing: Space.s2) {
            CoreTextField("Kind", placeholder: "device. or setting.set", text: $model.filter.kind)
            if !model.knownKinds.isEmpty {
                Menu("Known kinds") {
                    ForEach(model.knownKinds, id: \.self) { k in Button(k) { model.filter.kind = k } }
                }
                .menuStyle(.button).buttonStyle(.coreSecondary).fixedSize()
                .help("Pick a kind from the rows read so far")
            }
            CoreTextField("Target", placeholder: "device:d_… or secret", text: $model.filter.target)
            VStack(alignment: .leading, spacing: Space.s1) {
                CoreFieldLabel("Actor")
                CoreSegmented(
                    "Actor", segments: ActorFilter.allCases.map { CoreSegment($0, $0.rawValue.capitalized) },
                    selection: $model.filter.actor)
            }
            if !model.filter.isEmpty {
                Button("Clear") { model.clearFilters() }.buttonStyle(.coreSecondary).help("Clear every filter")
            }
        }
    }
}

private struct AuditList: View {
    @Bindable var model: AuditModel
    @Environment(\.corePalette) private var palette
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            VStack(spacing: Space.s1 / 2) {
                ForEach(model.items) { a in
                    row(a)
                }
            }
            .padding(Space.s1)
            .background(palette.glassCard, in: coreShape(Radius.cardMac))
            .coreFocusRing(focused, radius: Radius.cardMac, palette: palette)
            .focusable().focused($focused).focusEffectDisabled()
            .onKeyPress(.downArrow) {
                model.move(1)
                return .handled
            }
            .onKeyPress(.upArrow) {
                model.move(-1)
                return .handled
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Audit rows")
            .accessibilityHint("Arrow keys move between rows")
            HStack(spacing: Space.s3) {
                Text("Showing \(model.items.count)\(model.hasMore ? ", more available" : "")")
                    .font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
                Spacer()
                if let e = model.moreError { IssueLine(code: nil, text: e) }
                if model.hasMore {
                    Button("Load older") { Task { await model.loadOlder() } }
                        .buttonStyle(CoreButtonStyle(.secondary, size: .small, busy: model.loadingMore))
                        .help("Show the next \(AuditModel.pageSize) older rows")
                } else {
                    Text("End of the log").font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ a: AuditItem) -> some View {
        let on = model.selected == a.seq
        return HStack(spacing: Space.s2) {
            Text(AdminWords.when(a.at))
                .font(.system(size: MacTextSize.meta, design: .monospaced)).foregroundStyle(palette.text2).lineLimit(1)
                .frame(width: Space.s8 * 4, alignment: .leading)
            VStack(alignment: .leading, spacing: Space.s1 / 2) {
                MetaChip(text: a.action, mono: true).lineLimit(1)
                Text("\(a.actor.label)\(target(a).map { " · \($0)" } ?? "")").font(.system(size: MacTextSize.meta))
                    .foregroundStyle(palette.text2).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.s2).padding(.vertical, Space.s1).frame(minHeight: MacSize.controlLg + Space.s1)
        .background(on ? palette.navActive : .clear, in: coreShape(Radius.control))
        .overlay { if on { coreShape(Radius.control).strokeBorder(palette.navActiveEdge, lineWidth: 1) } }
        .contentShape(coreShape(Radius.control))
        .onTapGesture {
            model.selected = a.seq
            focused = true
        }
        .help("\(a.action), \(a.actor.label), \(AdminWords.when(a.at))")
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { model.selected = a.seq }
    }

    private func target(_ a: AuditItem) -> String? {
        switch (a.entityKind, a.entityRef) {
        case (let k?, let r?): "\(k):\(r)"
        case (let k?, nil): k
        case (nil, let r?): r
        default: nil
        }
    }
}

private struct AuditDetail: View {
    let item: AuditItem?
    @Environment(\.corePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            if let a = item {
                Text(a.action).font(.system(size: MacTextSize.headline, weight: .semibold, design: .monospaced))
                fact("Actor", a.actor.label)
                fact("Entity", [a.entityKind, a.entityRef].compactMap { $0 }.joined(separator: ":"), mono: true)
                fact("When", AdminWords.whenExact(a.at))
                fact("Sequence", String(a.seq), mono: true)
                CoreFieldLabel("details")
                Text(a.details).font(.system(size: MacTextSize.meta, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(Space.s2)
                    .background(palette.uDim, in: coreShape(Radius.control))
            } else {
                Text("Select a row to see its action, actor, entity and details.").foregroundStyle(palette.text2)
            }
        }
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .topLeading)
        .background(palette.glassCard, in: coreShape(Radius.cardMac))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Row details")
    }

    @ViewBuilder private func fact(_ k: String, _ v: String, mono: Bool = false) -> some View {
        if !v.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text(k).font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
                Text(v).font(
                    mono ? .system(size: MacTextSize.body, design: .monospaced) : .system(size: MacTextSize.body)
                )
                .textSelection(.enabled)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// How many rows fall in each slice of the loaded span: a picture of when things happened, with the span in words.
private struct Density: View {
    let cells: [Double]
    let from: Date
    let to: Date
    @Environment(\.corePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, v in
                    coreShape(1).fill(v <= 0 ? palette.track : palette.primary.opacity(0.3 + 0.7 * v))
                        .frame(maxWidth: .infinity).frame(height: Space.s1 + CGFloat(v) * (Space.s5 - Space.s1))
                }
            }
            .frame(height: Space.s5, alignment: .bottom)
            .accessibilityHidden(true)
            HStack {
                Text(AdminWords.when(from))
                Spacer()
                Text(AdminWords.when(to))
            }
            .font(.system(size: MacTextSize.meta, design: .monospaced)).foregroundStyle(palette.text2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rows over time, \(AdminWords.when(from)) to \(AdminWords.when(to))")
    }
}
