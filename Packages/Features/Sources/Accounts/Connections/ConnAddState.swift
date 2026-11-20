import Foundation

/// The five steps of the guided Add (D-21): pick a service, sign in on its own website, what AI may do, which
/// repositories (or projects, teams, channels), done.
enum ConnStep: Int, CaseIterable, Sendable {
    case service = 1
    case signIn, allow, choose, done
}

/// Read only, or read and change.
enum ConnMode: Hashable, Sendable { case read, write }

/// Where the Add dialog stands. Pure values and no I/O, so every move is a unit test; the model drives it.
struct ConnAddState: Equatable, Sendable {
    var step = ConnStep.service
    var kind: String?
    /// The connection the sign-in made (or the one being changed).
    var connection: Int64?
    /// Signing in again to a connection that is already there: nothing else is asked.
    var again = false
    /// Changing an existing connection's access: the last step says "Save", not "Connect".
    var editing = false
    /// The step an edit opened on: Back never goes before it.
    private(set) var floor = ConnStep.service
    var mode = ConnMode.read
    /// The write capabilities switched on. Always empty in read mode.
    var writes: Set<String> = []
    var picked: Set<String> = []
    var query = ""

    /// Open on a service already named (a tile on the empty page, or "Connect another").
    init(kind: String? = nil) {
        self.kind = kind
        if kind != nil { step = .signIn }
    }

    /// Open on an existing connection, at the step the menu item names.
    init(editing c: ConnItem, kind: ConnKind?, at step: ConnStep) {
        self.step = step
        self.kind = c.kind
        connection = c.id
        editing = true
        floor = step
        let writes = Set((kind?.capabilities ?? []).filter { $0.writes && c.allowed.contains($0.id) }.map(\.id))
        self.writes = writes
        mode = writes.isEmpty ? .read : .write
        picked = Set(c.only ?? [])
    }

    mutating func pick(service id: String) {
        kind = id
        mode = .read
        writes = []
        picked = []
        query = ""
        connection = nil
        again = false
        step = .signIn
    }

    /// The sign-in made (or renewed) connection `id`.
    mutating func signedIn(connection id: Int64) {
        connection = id
        step = again ? .done : .allow
    }

    /// The segmented control. Read and change turns every write switch on; read only turns them all off.
    mutating func set(mode m: ConnMode, in kind: ConnKind?) {
        mode = m
        writes = m == .write ? Set((kind?.capabilities ?? []).filter(\.writes).map(\.id)) : []
    }

    /// A write switch; ignored while the mode is read only (the switch is dimmed).
    mutating func toggle(_ capability: String) {
        guard mode == .write else { return }
        if writes.contains(capability) { writes.remove(capability) } else { writes.insert(capability) }
        // Every write switched off is the same as read only.
        if writes.isEmpty { mode = .read }
    }

    func isOn(_ c: ConnCapability) -> Bool { c.writes ? writes.contains(c.id) : true }

    /// The capability names a grant carries: every read one, plus the write ones switched on.
    func allowed(_ kind: ConnKind?) -> Set<String> {
        Set((kind?.capabilities ?? []).filter { !$0.writes || writes.contains($0.id) }.map(\.id))
    }

    mutating func toggle(pick id: String) {
        if picked.contains(id) { picked.remove(id) } else { picked.insert(id) }
    }

    /// The list under the search field: names, ids and second lines, any case.
    func visible(_ all: [ConnPick]) -> [ConnPick] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return all }
        return all.filter { [$0.name, $0.id, $0.detail ?? ""].contains { $0.lowercased().contains(q) } }
    }

    /// At least one: no choice would mean "everything", and the dialog never offers that by accident.
    var canFinish: Bool { !picked.isEmpty }

    /// The ids to save, in the list's order, then any picked ones the list no longer shows.
    func chosen(order: [ConnPick]) -> [String] {
        let known = order.map(\.id).filter(picked.contains)
        return known + picked.subtracting(known).sorted()
    }

    var countLine: String { "\(picked.count) picked" }

    mutating func next() {
        switch step {
        case .allow: step = .choose
        case .choose: step = .done
        default: break
        }
    }

    /// Back one step; the first two steps go back to the tiles, and editing never goes back past what it opened on.
    mutating func back() {
        guard let prior = ConnStep(rawValue: step.rawValue - 1), step != .done else { return }
        if prior.rawValue < floor.rawValue { return }
        step = prior == .signIn && connection != nil ? .service : prior
    }

    /// What the last step says: "Your assistant can read 3 repositories. Nothing can be changed."
    func doneLine(noun: String) -> String {
        let n = picked.count
        let what = ConnAccess.noun(noun, count: n)
        return mode == .read
            ? "Your assistant can read \(n) \(what). Nothing can be changed."
            : "Your assistant can read and change \(n) \(what)."
    }
}
