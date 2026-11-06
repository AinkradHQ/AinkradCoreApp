import CoreUI
import SwiftUI

/// Settings, Security, Audit: what happened on your Core, newest first, as sentences. Filter by area, by who, or find a
/// name; ↑ ↓ move through the rows and the panel at the right says everything about the one picked.
struct AuditSection: View {
    let admin: AdminModel

    var body: some View {
        let model = admin.audit!
        AdminScreen(
            admin: admin, what: "The audit log",
            intro:
                "Everything that changed on your Core: who did it, to what, and when. It never holds terminal output or secret values.",
            state: model.state,
            empty: (
                "Nothing recorded yet", "Rows appear as devices pair, settings change and secrets are used.", "doc.text"
            ),
            retry: { Task { await model.reload() } }
        ) {
            VStack(alignment: .leading, spacing: Space.s4) {
                AuditFilters(model: model)
                if let d = model.density() { Activity(cells: d.cells, from: d.from, to: d.to) }
                if model.items.isEmpty {
                    StateCard(
                        symbol: "magnifyingglass", title: "Nothing matches",
                        text: "No rows match these filters."
                    ) { Button("Show everything") { model.clearFilters() }.buttonStyle(.coreSecondary) }
                } else {
                    HStack(alignment: .top, spacing: Space.s3) {
                        AuditList(admin: admin, model: model)
                        AuditDetail(admin: admin, item: model.selection).frame(width: Space.s8 * 10)
                    }
                }
            }
            .foregroundStyle(GlassInk.primary)
        }
        .task { await model.reload() }
        .accessibilityIdentifier("audit")
    }
}

/// Audit rows in plain words: the area a kind belongs to, its verb, and what it was done to.
enum AuditWords {
    struct Area: Identifiable {
        let id: String
        let title: String
        let symbol: String
        let hue: Color
    }

    static let areas: [Area] = [
        Area(id: "device.", title: "Devices", symbol: "laptopcomputer.and.iphone", hue: GlassInk.blue),
        Area(id: "pairing.", title: "Pairing", symbol: "qrcode", hue: GlassInk.blue),
        Area(id: "auth.", title: "Sign-in", symbol: "lock.shield.fill", hue: GlassInk.blue),
        Area(id: "setting.", title: "Settings", symbol: "slider.horizontal.3", hue: GlassInk.blue),
        Area(id: "secret.", title: "Secrets", symbol: "key.fill", hue: GlassInk.blue),
        Area(id: "account.", title: "Accounts", symbol: "person.crop.square.fill", hue: GlassInk.blue),
        Area(id: "terminal.", title: "Terminals", symbol: "terminal.fill", hue: GlassInk.blue),
        Area(id: "agent.", title: "Agents", symbol: "play.fill", hue: GlassInk.blue),
    ]

    static func area(_ action: String) -> Area {
        areas.first { action.hasPrefix($0.id) }
            ?? Area(id: "", title: "Core", symbol: "gearshape.fill", hue: GlassInk.slate)
    }

    private static let verbs: [String: String] = [
        "created": "created", "deleted": "deleted", "set": "changed", "leased": "lent", "claimed": "claimed",
        "cleared": "cleared", "lockout_cleared": "cleared the lock on", "lockout": "locked", "revoked": "revoked",
        "renamed": "renamed", "enrolled": "added", "replaced": "replaced",
        "secret_replaced": "gave a new key to", "state_set": "turned on or off", "cap_set": "changed the limit of",
        "approved": "approved", "rejected": "turned down", "ended": "ended", "killed": "stopped",
        "step_up": "used Touch ID on",
        "approval_decided": "answered an approval in", "resumed": "resumed",
        "tested": "tested the key of", "auth_failed": "saw a refused key on",
        "auth_inconclusive": "couldn't confirm a refused key on", "session_limits_set": "changed the session limits of",
        "limit_set": "set a provider limit on", "limit_cleared": "cleared a provider limit on",
        "login_started": "started a sign-in for", "login_failed": "had a failed sign-in for",
        "login_cancelled": "stopped a sign-in for",
    ]

    /// `You created secret github-token-test`, `The Core cleared the lock on 198.51.100.7`.
    static func sentence(_ a: AuditItem, title: (String) -> String?) -> (who: String, verb: String, what: String) {
        let who = a.actor == .system ? "Your Core" : a.actor.label
        let tail = a.action.split(separator: ".", maxSplits: 1).dropFirst().first.map(String.init) ?? a.action
        let verb = verbs[tail] ?? tail.replacingOccurrences(of: "_", with: " ")
        if tail == "scopes_set" { return (who, "changed what", object(a, title: title) + " may do") }
        return (who, verb, object(a, title: title))
    }

    static func object(_ a: AuditItem, title: (String) -> String?) -> String {
        guard let ref = a.entityRef else { return a.entityKind ?? "" }
        switch a.entityKind {
        case "setting": return "“\(title(ref) ?? ref)”"
        case "lockout": return ref.split(separator: ":").dropFirst().joined(separator: ":")
        case "secret": return "secret \(ref)"
        case let k?: return "a \(k)"
        case nil: return ref
        }
    }
}

/// Filters as tiles: the area at the top, then who, then a search for a name.
private struct AuditFilters: View {
    @Bindable var model: AuditModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.s2) {
                    AppFilterTile(title: "All", count: -1, on: model.filter.kind.isEmpty, key: "") {
                        model.filter.kind = ""
                    }
                    ForEach(AuditWords.areas) { a in
                        AppFilterTile(title: a.title, count: -1, on: model.filter.kind == a.id, key: "") {
                            model.filter.kind = a.id
                        }
                    }
                }
            }
            HStack(spacing: Space.s3) {
                CoreTextField("Find", placeholder: "A device, secret or setting", text: $model.filter.target)
                    .frame(maxWidth: .infinity)
                CoreSegmented(
                    "Who",
                    segments: [
                        CoreSegment(ActorFilter.any, "Anyone", symbol: "person.2.fill"),
                        CoreSegment(ActorFilter.user, "People", symbol: "person.fill"),
                        CoreSegment(ActorFilter.system, "Your Core", symbol: "server.rack"),
                    ],
                    selection: $model.filter.actor
                )
                .fixedSize()
                if !model.filter.isEmpty {
                    AppActionTile(title: "Clear", symbol: "xmark", key: "", hue: GlassInk.slate) {
                        model.clearFilters()
                    }
                    .transition(.opacity)
                }
            }
        }
        .animation(Motion.out(Motion.ui), value: model.filter)
    }
}

private struct AuditList: View {
    let admin: AdminModel
    @Bindable var model: AuditModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            ScrollViewReader { proxy in
                VStack(spacing: Space.s1 / 2) {
                    ForEach(Array(model.items.enumerated()), id: \.element.id) { i, a in
                        if i == 0 || !Calendar.current.isDate(a.at, inSameDayAs: model.items[i - 1].at) {
                            Text(day(a.at)).font(.system(size: MacTextSize.meta, weight: .semibold))
                                .foregroundStyle(GlassInk.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, Space.s2).padding(.top, i == 0 ? 0 : Space.s2)
                        }
                        row(a).id(a.seq)
                    }
                }
                .onChange(of: model.selected) { _, s in
                    guard let s else { return }
                    withAnimation(Motion.out(Motion.ui)) { proxy.scrollTo(s, anchor: .center) }
                }
            }
            .padding(Space.s2)
            .coreWell()
            .focusable().focused($focused).focusEffectDisabled()
            .onKeyPress(phases: .down) { press in
                switch press.key {
                case .downArrow: model.move(1)
                case .upArrow: model.move(-1)
                case .home: model.move(-model.items.count)
                case .end: model.move(model.items.count)
                default: return .ignored
                }
                return .handled
            }
            .onAppear {
                focused = true
                if model.selected == nil { model.move(1) }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Audit rows")
            .accessibilityHint("Arrow keys move between rows")
            HStack(spacing: Space.s3) {
                Text("\(model.items.count) shown").font(.system(size: MacTextSize.meta))
                    .foregroundStyle(GlassInk.secondary)
                Spacer()
                if let e = model.moreError { IssueLine(code: nil, text: e) }
                if model.hasMore {
                    AppActionTile(title: "Older", symbol: "arrow.down", key: "", hue: GlassInk.slate) {
                        Task { await model.loadOlder() }
                    }
                    .opacity(model.loadingMore ? 0.5 : 1)
                    .help("Show the next \(AuditModel.pageSize) older rows")
                } else {
                    Label("That's the start of the log", systemImage: "flag.checkered")
                        .font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func day(_ d: Date) -> String {
        if Calendar.current.isDateInToday(d) { return "Today" }
        if Calendar.current.isDateInYesterday(d) { return "Yesterday" }
        return d.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    private func row(_ a: AuditItem) -> some View {
        let on = model.selected == a.seq
        let area = AuditWords.area(a.action)
        let s = AuditWords.sentence(a) { admin.registry.item($0).map(SettingWords.title) }
        return HStack(spacing: Space.s3) {
            IconTile(area.symbol, hue: area.hue, size: 28)
            (Text(s.who).fontWeight(.semibold) + Text(" \(s.verb) ") + Text(s.what).fontWeight(.semibold))
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: Space.s2)
            Text(a.at.formatted(date: .omitted, time: .shortened)).font(
                .system(size: MacTextSize.meta).monospacedDigit()
            )
            .foregroundStyle(GlassInk.secondary)
        }
        .padding(.horizontal, Space.s2).frame(height: 40)
        .background(on ? area.hue.opacity(0.16) : .clear, in: coreShape(Radius.control))
        .overlay { if on { coreShape(Radius.control).strokeBorder(area.hue.opacity(0.55), lineWidth: 1) } }
        .contentShape(coreShape(Radius.control))
        .onTapGesture {
            model.selected = a.seq
            focused = true
        }
        .animation(Motion.out(Motion.ui), value: on)
        .help("\(a.action) \(a.entityRef ?? "")")
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { model.selected = a.seq }
    }
}

/// Everything about one row: the sentence, then who, what, when and the details as plain pairs.
private struct AuditDetail: View {
    let admin: AdminModel
    let item: AuditItem?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            if let a = item {
                let area = AuditWords.area(a.action)
                let s = AuditWords.sentence(a) { admin.registry.item($0).map(SettingWords.title) }
                IconTile(area.symbol, hue: area.hue, size: 44, bounce: a.seq)
                (Text(s.who).fontWeight(.semibold) + Text(" \(s.verb) ") + Text(s.what).fontWeight(.semibold))
                    .font(.system(size: MacTextSize.headline)).fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: Space.s2) {
                    fact("clock.fill", AdminWords.whenExact(a.at))
                    fact(a.actor == .system ? "server.rack" : "person.fill", a.actor.label)
                    fact(area.symbol, area.title)
                }
                let pairs = Self.pairs(a.details)
                if !pairs.isEmpty {
                    VStack(alignment: .leading, spacing: Space.s1) {
                        ForEach(pairs, id: \.0) { k, v in
                            HStack(alignment: .firstTextBaseline) {
                                Text(k.replacingOccurrences(of: "_", with: " ").capitalized).foregroundStyle(
                                    GlassInk.secondary)
                                Spacer(minLength: Space.s2)
                                Text(v).font(.system(size: MacTextSize.body, design: .monospaced)).textSelection(
                                    .enabled
                                )
                                .multilineTextAlignment(.trailing)
                            }
                        }
                    }
                    .padding(Space.s3)
                    .background(.black.opacity(0.2), in: coreShape(Radius.control))
                }
            } else {
                Text("Pick a row to see everything about it.").foregroundStyle(GlassInk.secondary)
            }
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .topLeading)
        .coreWell()
        .help(item.map { "Entry \($0.seq) · \($0.action)" } ?? "")
        .animation(Motion.out(Motion.ui), value: item?.seq)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Row details")
    }

    private func fact(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol).foregroundStyle(GlassInk.primary)
    }

    /// A details object as name and value pairs; a value that is a list or object is shown compactly.
    static func pairs(_ json: String) -> [(String, String)] {
        guard let data = json.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return json.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : [("Details", json)] }
        return obj.keys.sorted().map { k in
            let v = obj[k]
            let text: String =
                switch v {
                case let a as [Any]: a.map { "\($0)" }.joined(separator: ", ")
                case let s as String: s
                case let n as NSNumber: n.stringValue
                default: v.map { "\($0)" } ?? ""
                }
            return (k, text)
        }
    }
}

/// When things happened across the rows loaded: bars, the busiest slice tallest.
private struct Activity: View {
    let cells: [Double]
    let from: Date
    let to: Date

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            HStack(alignment: .bottom, spacing: Space.s1 / 2) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, v in
                    coreShape(2)
                        .fill(
                            v <= 0
                                ? AnyShapeStyle(GlassInk.track.opacity(0.5))
                                : AnyShapeStyle(
                                    LinearGradient(
                                        colors: [GlassInk.blue.opacity(0.5), GlassInk.blue], startPoint: .bottom,
                                        endPoint: .top))
                        )
                        .frame(maxWidth: .infinity).frame(height: 4 + CGFloat(v) * 28)
                }
            }
            .frame(height: 32, alignment: .bottom)
            .accessibilityHidden(true)
            HStack {
                Text(from.formatted(date: .abbreviated, time: .shortened))
                Spacer()
                Text("When things happened").fontWeight(.semibold)
                Spacer()
                Text(to.formatted(date: .abbreviated, time: .shortened))
            }
            .font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rows over time, \(AdminWords.when(from)) to \(AdminWords.when(to))")
    }
}
