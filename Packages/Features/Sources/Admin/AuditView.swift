import CoreUI
import SwiftUI

/// Activity, Audit: what happened on your Core, newest first, as sentences. Filter by area, by who, or find a
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
        Area(id: "auth.", title: "Sign-in", symbol: "lock.shield.fill", hue: GlassInk.red),
        Area(id: "setting.", title: "Settings", symbol: "slider.horizontal.3", hue: GlassInk.blue),
        Area(id: "secret.", title: "Secrets", symbol: "key.fill", hue: GlassInk.blue),
        Area(id: "account.", title: "Accounts", symbol: "person.crop.circle.fill", hue: GlassInk.blue),
        Area(id: "connection.", title: "Connections", symbol: "link", hue: GlassInk.blue),
        Area(id: "terminal.", title: "Terminals", symbol: "terminal.fill", hue: GlassInk.blue),
        Area(id: "agent.", title: "AI sessions", symbol: "sparkles", hue: GlassInk.blue),
        Area(id: CodeModeAudit.areaPrefix, title: "Code Mode", symbol: "curlybraces", hue: GlassInk.blue),
        Area(id: "brain.ai.", title: "Brain, by AI sessions", symbol: "books.vertical.fill", hue: GlassInk.blue),
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
        "login_cancelled": "stopped a sign-in for", "updated": "changed", "disabled": "turned off",
        "enabled": "turned on", "used": "used", "use": "used", "granted": "let an AI session use",
        "rotated": "gave a new token to", "default_set": "made the default",
        "default_cleared": "cleared the default of",
    ]

    /// `You created secret github-token-test`, `The Core cleared the lock on 198.51.100.7`.
    static func sentence(
        _ a: AuditItem, deviceName: (String) -> String? = { _ in nil }, title: (String) -> String?
    ) -> (who: String, verb: String, what: String) {
        if let code = CodeModeAudit.sentence(a) { return code }
        let who = a.actor == .system ? "Your Core" : a.actor.label
        let tail = a.action.split(separator: ".", maxSplits: 1).dropFirst().first.map(String.init) ?? a.action
        let verb = verbs[tail] ?? tail.replacingOccurrences(of: "_", with: " ")
        let what = object(a, deviceName: deviceName, title: title)
        if tail == "scopes_set" { return (who, "changed what", what + " may do") }
        return (who, verb, what)
    }

    /// What started a row, in words; a row from before the Core recorded origins is "Unknown".
    static func origin(_ o: AuditOrigin?) -> (label: String, symbol: String) {
        switch o?.kind {
        case "person": ("A person", "person.fill")
        case "schedule": ("A schedule", "clock.fill")
        case "brain_import": ("A Brain import", "square.and.arrow.down.fill")
        case "brain_distil": ("Brain distilling", "sparkles")
        case "ai_session": ("An AI session", "sparkles")
        case "handoff": ("A hand-off", "arrow.triangle.branch")
        case "system": ("Your Core", "server.rack")
        default: ("Unknown", "questionmark.circle")
        }
    }

    /// "A schedule" or "An AI session, started by a person" when the chain began somewhere else.
    static func originSentence(_ o: AuditOrigin?, deviceName: (String) -> String? = { _ in nil }) -> String {
        guard let o else { return origin(nil).label }
        let first = origin(o).label
        if o.rootKind == "person", o.kind != "person", let name = o.rootReference.flatMap(deviceName) {
            return "\(first), started by \(name)"
        }
        return o.rootKind == o.kind
            ? first
            : "\(first), started by \(origin(AuditOrigin(kind: o.rootKind, reference: nil, rootKind: o.rootKind, rootReference: nil)).label.lowercased())"
    }

    /// An opaque id the Core made (`d_71ws…`, `p_1`, `req4k2`): never shown in a sentence, only as hover help.
    static func isOpaqueID(_ s: String) -> Bool {
        s.range(
            of: #"^(?:[a-z]{1,4}_(?=[A-Za-z0-9]*\d)[A-Za-z0-9]{1,}|req[A-Za-z0-9]*\d[A-Za-z0-9]*)$"#,
            options: .regularExpression)
            != nil
    }

    /// The ids behind a row, for its hover help.
    static func ids(_ a: AuditItem) -> String? {
        var all = [a.entityRef].compactMap { $0 }
        if let d = detailsDict(a) { all += d.values.compactMap { $0 as? String }.filter(isOpaqueID) }
        let seen = all.filter(isOpaqueID)
        return seen.isEmpty ? nil : seen.joined(separator: ", ")
    }

    /// The details of a row split for the side panel: plain pairs (ids replaced by a device name or "a device"), and
    /// the technical ones (the raw ids, the entry number and the action code) that sit behind a folded disclosure.
    static func detailRows(_ a: AuditItem, deviceName: (String) -> String? = { _ in nil }) -> (
        plain: [(String, String)], technical: [(String, String)]
    ) {
        var plain: [(String, String)] = []
        var technical: [(String, String)] = []
        for (k, v) in pairs(a.details) {
            let key = k.replacingOccurrences(of: "_", with: " ")
            if k == "args_sha256" {  // a fingerprint of the arguments: for matching, not for reading
                technical.append((key, v))
                continue
            }
            if CodeModeAudit.isRow(a.action), let p = CodeModeAudit.plain(k, v) {
                if !p.key.isEmpty { plain.append((p.key, p.value)) }
                if k != "ms" && p.key != "" { technical.append((key, v)) }
                continue
            }
            guard isOpaqueID(v) else {
                plain.append((key, v))
                continue
            }
            let kind = k.hasPrefix("by_") ? String(k.dropFirst(3)) : k
            plain.append((key, (kind == "device" ? deviceName(v) : nil) ?? thing(kind)))
            technical.append((key, v))
        }
        if let ref = a.entityRef, isOpaqueID(ref), !technical.contains(where: { $0.1 == ref }) {
            technical.append(("Id", ref))
        }
        technical += [("Entry", "\(a.seq)"), ("Action", a.action)]
        return (plain, technical)
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

    private static func detailsDict(_ a: AuditItem) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: Data(a.details.utf8))) as? [String: Any]
    }

    private static func thing(_ kind: String) -> String {
        [
            "device": "a device", "pairing": "a pairing", "session": "a session", "terminal": "a terminal",
            "agent": "an AI session", "account": "an account", "connection": "a connection",
        ][kind] ?? "a \(kind)"
    }

    /// A row with no entity (`pairing.created`, `api.refused`) names what it was about in its details: `pairing p_1`.
    static func fromDetails(_ a: AuditItem, deviceName: (String) -> String? = { _ in nil }) -> String? {
        guard let d = detailsDict(a) else { return nil }
        for key in ["pairing", "device", "account", "agent", "secret", "connection", "terminal", "session"] {
            if let v = d[key] as? String, !v.isEmpty { return named(key, v, deviceName) }
        }
        return (d["path"] as? String).map { "a request to \($0)" }
    }

    private static func named(_ kind: String, _ ref: String, _ deviceName: (String) -> String?) -> String {
        if kind == "device", let n = deviceName(ref) { return "“\(n)”" }
        return isOpaqueID(ref) ? thing(kind) : "\(kind) \(ref)"
    }

    static func object(_ a: AuditItem, deviceName: (String) -> String? = { _ in nil }, title: (String) -> String?)
        -> String
    {
        guard let ref = a.entityRef else { return fromDetails(a, deviceName: deviceName) ?? a.entityKind ?? "" }
        switch a.entityKind {
        case "setting": return "“\(title(ref) ?? ref)”"
        case "lockout": return ref.split(separator: ":").dropFirst().joined(separator: ":")
        case let k?: return named(k, ref, deviceName)
        case nil: return ref
        }
    }
}

/// Filters as tiles: the area at the top, then who, then a search for a name.
private struct AuditFilters: View {
    @Environment(\.corePalette) private var palette
    @Bindable var model: AuditModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Space.s2) {
                        chip("All", "square.grid.2x2.fill", GlassInk.slate, on: model.filter.kind.isEmpty) {
                            model.filter.kind = ""
                        }
                        ForEach(AuditWords.areas) { a in
                            chip(a.title, a.symbol, a.hue, on: model.filter.kind == a.id) { model.filter.kind = a.id }
                                .id(a.id)
                        }
                    }
                }
                // The chosen area stays in view when the row of areas is wider than the page.
                .onAppear { proxy.scrollTo(model.filter.kind, anchor: .center) }
                .onChange(of: model.filter.kind) { _, k in
                    withAnimation(.smooth(duration: 0.25)) { proxy.scrollTo(k, anchor: .center) }
                }
            }
            HStack(spacing: Space.s3) {
                HStack(spacing: Space.s2) {
                    Image(systemName: "magnifyingglass").foregroundStyle(GlassInk.secondary)
                    TextField("Find a name: a device, secret or setting", text: $model.filter.target)
                        .textFieldStyle(.plain)
                    if !model.filter.target.isEmpty {
                        Button {
                            model.filter.target = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain).foregroundStyle(GlassInk.secondary)
                    }
                }
                .padding(.horizontal, Space.s3).frame(height: 34)
                .background(GlassInk.well, in: coreShape(Radius.control))
                .focusEffectDisabled()
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
                chip(
                    "Nobody watching", "moon.zzz.fill", GlassInk.slate, on: model.filter.nobodyWatching
                ) { model.filter.nobodyWatching.toggle() }
                .help("Only rows a person did not start: schedules, Brain, AI sessions and the Core itself")
                if !model.filter.isEmpty {
                    AppActionTile(title: "Clear", symbol: "xmark", key: "", hue: GlassInk.slate) {
                        model.clearFilters()
                    }
                    .transition(.opacity)
                }
            }
        }
        .animation(.smooth(duration: 0.3), value: model.filter)
    }

    private func chip(_ title: String, _ symbol: String, _ hue: Color, on: Bool, run: @escaping () -> Void) -> some View
    {
        Button(action: run) {
            Label(title, systemImage: symbol).coreFont(size: MacTextSize.body, weight: .semibold)
                .foregroundStyle(on ? GlassInk.primary : GlassInk.secondary)
                .padding(.horizontal, Space.s3).frame(height: 30)
                .background(on ? palette.navActive : GlassInk.well, in: coreShape(Radius.control))
                .contentShape(coreShape(Radius.control))
        }
        .buttonStyle(.plain)
    }
}

private struct AuditList: View {
    let admin: AdminModel
    @Bindable var model: AuditModel
    @FocusState private var focused: Bool
    @Environment(\.corePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            ScrollViewReader { proxy in
                LazyVStack(spacing: 2) {
                    ForEach(Array(model.items.enumerated()), id: \.element.id) { i, a in
                        if i == 0 || !Calendar.current.isDate(a.at, inSameDayAs: model.items[i - 1].at) {
                            Text(day(a.at)).coreFont(size: MacTextSize.meta, weight: .semibold)
                                .foregroundStyle(GlassInk.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, Space.s2).padding(.top, i == 0 ? 0 : Space.s2)
                        }
                        row(a).modifier(RiseIn(index: i)).id(a.seq)
                    }
                }
                .onChange(of: model.selected) { _, s in
                    guard let s else { return }
                    withAnimation(.smooth(duration: 0.25)) { proxy.scrollTo(s, anchor: .center) }
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
                Text("\(model.items.count) shown").coreFont(size: MacTextSize.meta)
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
                        .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
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
        let s = AuditWords.sentence(a, deviceName: { admin.deviceNames[$0] }) {
            admin.registry.item($0).map(SettingWords.title)
        }
        return HStack(spacing: Space.s3) {
            IconTile(area.symbol, hue: area.hue, size: 28)
            (Text(s.who).bold() + Text(" \(s.verb) ") + Text(s.what).bold())
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: Space.s2)
            Text(AuditWords.origin(a.origin).label).coreFont(size: MacTextSize.meta)
                .foregroundStyle(a.origin == nil ? GlassInk.secondary.opacity(0.6) : GlassInk.secondary)
                .lineLimit(1).frame(width: Space.s8 * 2.5, alignment: .leading)
            Text(a.at.formatted(date: .omitted, time: .shortened)).coreFont(size: MacTextSize.meta).monospacedDigit()
                .foregroundStyle(GlassInk.secondary)
        }
        .padding(.horizontal, Space.s2).frame(height: 40)
        .background(on ? palette.navActive : .clear, in: coreShape(Radius.control))
        .contentShape(coreShape(Radius.control))
        .onTapGesture {
            model.selected = a.seq
            focused = true
        }
        .animation(.smooth(duration: 0.2), value: on)
        .help([a.action, AuditWords.ids(a)].compactMap { $0 }.joined(separator: " · "))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { model.selected = a.seq }
    }
}
