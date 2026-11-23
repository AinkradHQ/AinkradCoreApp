import CoreUI
import SwiftUI

/// The side panel beside a Rules or Knowledge list: what it is, (for a rule) the Follow switch, where it applies, how sure
/// Brain is, when it learned it and why it thinks so, then Edit and Forget (archived, Undo in the toast).
struct RecordPanel: View {
    let brain: BrainModel
    let record: BrainAreaRecordWire
    var topic: String?
    @Environment(\.accessibilityReduceMotion) private var reduce

    private var isRule: Bool { brain.calm.page == .rules }
    private var kind: RuleKind? { record.kind.flatMap(RuleKind.init(rawValue:)) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            if isRule, let kind {
                KindTile(kind: kind, size: Space.s8 + Space.s2)
            } else {
                Text(label).coreFont(size: MacTextSize.body, weight: .semibold).foregroundStyle(GlassInk.secondary)
            }
            Text(title).coreFont(size: MacTextSize.title, weight: .semibold)
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                .contentTransition(.opacity)
            if isRule, brain.calm.v101 { follow }
            Grid(alignment: .leading, horizontalSpacing: Space.s4, verticalSpacing: Space.s2) {
                GridRow {
                    key(isRule ? "Applies to" : "Place")
                    places
                }
                if let topic {
                    GridRow {
                        key("Topic")
                        Text(topic)
                    }
                }
                GridRow {
                    key("How sure")
                    HStack(spacing: Space.s2) {
                        SureBars(support: record.support)
                        Text(BrainSure.words(record.support)).foregroundStyle(GlassInk.secondary)
                    }
                }
                GridRow {
                    key("Learned")
                    Text(ago(record.createdAt))
                }
            }
            .coreFont(size: MacTextSize.body)
            Text(isRule ? "Why Brain thinks so" : "Where it came from")
                .coreFont(size: MacTextSize.body, weight: .semibold).foregroundStyle(GlassInk.secondary)
            evidence(
                "doc.on.doc", "Seen in \(BrainWords.plural(record.support, "session", "sessions"))",
                "Last seen \(SyncWords.date(record.seenAt).map { SyncWords.agoInLine($0) } ?? "–")")
            evidence("folder", "Kept in \(record.roomName)", "Open the place to see what it read", open: openPlace)
            HStack {
                if isRule, brain.calm.v101 {
                    Button {
                        BrainSheets.rule(brain, editing: record)
                    } label: {
                        Label("Edit Rule…", systemImage: "pencil")
                    }
                    .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                    .help("Change this rule's words, kind or place")
                }
                Spacer(minLength: Space.s2)
                Button {
                    brain.forget(record)
                } label: {
                    Label("Forget", systemImage: "trash")
                }
                .buttonStyle(CoreButtonStyle(.quietDanger, size: .small))
                .keyboardShortcut(.delete, modifiers: .command)
                .help("Forget this (⌘⌫). It is kept in the archive, and Undo brings it back.")
            }
            .padding(.top, Space.s1)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .coreWell()
        .animation(Motion.calm(Motion.out(Motion.ui), reduce), value: record.id)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("brain-record-panel")
    }

    private var label: String {
        switch record.type {
        case "decision": "Decision"
        case "fact": "Fact"
        case "preference": "Preference"
        case "rule": "Rule"
        default: "Event"
        }
    }

    private var title: String {
        guard isRule, let kind else { return record.body }
        let b = BrainCalmModel.Learned.lowerFirst(record.body)
        return "\(kind.title): \(b)\(b.hasSuffix(".") ? "" : ".")"
    }

    private var follow: some View {
        HStack(spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Follow this rule").coreFont(size: MacTextSize.body, weight: .semibold)
                Text("Turn off to keep it without using it").coreFont(size: MacTextSize.meta)
                    .foregroundStyle(GlassInk.secondary)
            }
            Spacer(minLength: Space.s2)
            CoreSwitch(
                isOn: Binding(
                    get: { record.following ?? true }, set: { on in Task { await brain.calm.follow(record, on) } })
            )
            .fixedSize()
            .accessibilityLabel("Follow this rule")
            .help((record.following ?? true) ? "Keep this rule without using it" : "Use this rule again")
        }
        .padding(Space.s3)
        .background(GlassInk.well, in: coreShape(Radius.control))
    }

    @ViewBuilder private var places: some View {
        if record.everywhere == true {
            PlaceChip(name: "", everywhere: true)
        } else {
            HStack(spacing: Space.s1) {
                ForEach(record.rooms?.map(\.name) ?? [record.roomName], id: \.self) { PlaceChip(name: $0) }
            }
        }
    }

    private func key(_ s: String) -> some View { Text(s).foregroundStyle(GlassInk.secondary) }

    private func evidence(_ symbol: String, _ title: String, _ sub: String, open: (() -> Void)? = nil) -> some View {
        Button {
            open?()
        } label: {
            HStack(alignment: .top, spacing: Space.s2) {
                Image(systemName: symbol).foregroundStyle(GlassInk.secondary).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).coreFont(size: MacTextSize.body)
                    Text(sub).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                }
                Spacer(minLength: 0)
                if open != nil {
                    Image(systemName: "chevron.right").coreFont(size: MacTextSize.meta)
                        .foregroundStyle(GlassInk.secondary).accessibilityHidden(true)
                }
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GlassInk.well, in: coreShape(Radius.control))
            .contentShape(coreShape(Radius.control))
        }
        .buttonStyle(.plain)
        .allowsHitTesting(open != nil)
    }

    private func ago(_ iso: String) -> String { SyncWords.date(iso).map { SyncWords.ago($0) } ?? "–" }

    private func openPlace() {
        brain.view(record.room)
        brain.go(.rooms)
        brain.placeOpen = true
        Task { await brain.inspect(record.room) }
    }
}

/// A rule kind's tile: Always green, Never red, Prefer in the accent.
struct KindTile: View {
    let kind: RuleKind
    var size: CGFloat = Space.s6 + Space.s1
    @Environment(\.corePalette) private var palette
    @Environment(\.coreAccent) private var accent

    var body: some View {
        BrainTile(symbol: kind.symbol, size: size, tint: tint)
    }

    private var tint: Color {
        switch kind {
        case .always: palette.success
        case .never: GlassInk.red
        case .prefer: GlassInk.accentInk(accent)
        }
    }
}
