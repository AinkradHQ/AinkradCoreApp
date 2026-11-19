import CoreKit
import Foundation

/// What step 4 shows while it reads the service's list.
enum ConnPickLoad: Equatable, Sendable {
    case idle
    case loading
    case ready(ConnPicks)
    case failed(String)
}

/// The guided Add (D-21): the model side of the five-step dialog. The steps themselves are `ConnAddState`.
extension ConnectionsModel {
    /// "Connect": the tiles first; with a service named, its sign-in starts at once.
    func beginAdd(kind: String? = nil) {
        stopFlow()
        add = ConnAddState(kind: kind)
        resetAdd()
        ConnDialogs.openAdd(self)
        if let kind { Task { await signIn(kind) } }
    }

    /// "What AI may do…" (step 3) and "Choose repositories…" (step 4) on a connection that is there.
    func beginEdit(_ c: ConnItem, at step: ConnStep) {
        stopFlow()
        add = ConnAddState(editing: c, kind: kind(c.kind), at: step)
        resetAdd()
        ConnDialogs.openAdd(self)
        if step == .choose { Task { await loadPicks() } }
    }

    /// "Sign in again": the same sign-in, replacing the credential of connection `c`, then straight to done.
    func beginAgain(_ c: ConnItem) {
        stopFlow()
        var a = ConnAddState(kind: c.kind)
        a.again = true
        a.connection = c.id
        add = a
        resetAdd()
        again = c.id
        ConnDialogs.openAdd(self)
        Task { await signIn(c.kind) }
    }

    private func resetAdd() {
        picks = .idle
        addError = nil
    }

    /// Step 1: a tile.
    func pick(service id: String) {
        stopFlow()
        add?.pick(service: id)
        addError = nil
        Task { await signIn(id) }
    }

    /// Start the sign-in and open the service's own page. The page is the service's, never ours: no password is typed here.
    func signIn(_ kind: String) async {
        await startFlow(kind)
        if case .waiting? = flow?.step { openSignIn() }
    }

    func retrySignIn() {
        guard let k = add?.kind else { return }
        let again = add?.again == true ? add?.connection : nil
        stopFlow()
        self.again = again
        Task { await signIn(k) }
    }

    /// The flow's step moved (the model's `flow` observer): a finished sign-in moves the dialog on.
    func advance() {
        guard add?.step == .signIn, case .connected(let id)? = flow?.step else { return }
        add?.signedIn(connection: id)
        if add?.step == .allow { picks = .idle }
    }

    func addBack() {
        guard var a = add else { return }
        if a.step == .signIn { stopFlow() }
        a.back()
        add = a
        addError = nil
    }

    /// Step 3 to 4: read the service's list.
    func addNext() {
        add?.next()
        if add?.step == .choose { Task { await loadPicks() } }
    }

    func loadPicks() async {
        guard let id = add?.connection, let service else { return }
        picks = .loading
        do {
            let p = try await service.picks(id)
            picks = .ready(p)
            // Changing the access of a connection that reached everything: start with everything ticked, so a change to what
            // AI may do never silently narrows where it can go.
            if let a = add, a.editing, a.picked.isEmpty, item(id)?.only == nil {
                add?.picked = Set(p.items.map(\.id))
            }
        } catch {
            picks = .failed(ConnSay.plain(error))
        }
    }

    /// Step 4: save the grant (one Touch ID), then the done step.
    func finishAdd() async {
        guard let a = add, let id = a.connection, a.canFinish else { return }
        if item(id) == nil { await reload() }
        guard let c = item(id), let k = kind(c.kind) else {
            addError = "That connection isn't there any more. Nothing was changed."
            return
        }
        let order: [ConnPick]
        if case .ready(let p) = picks { order = p.items } else { order = [] }
        addError = nil
        if await setAccess(c, allowed: a.allowed(k), only: a.chosen(order: order)) {
            add?.next()
        } else {
            addError = writeError["access-\(c.id)"]
        }
    }

    func closeAdd() {
        stopFlow()
        add = nil
        picks = .idle
        addError = nil
    }

    // MARK: disconnect with Undo

    /// The rows, without the one just disconnected.
    var shown: [ConnItem] { items.filter { !pendingDelete.contains($0.id) } }

    /// Gone from the list at once, with Undo for a few seconds; only then does the Core delete it (its sign-in cannot be
    /// brought back, so nothing irreversible happens inside the Undo window).
    func disconnectWithUndo(_ c: ConnItem) {
        pendingDelete.insert(c.id)
        let name = kind(c.kind)?.name ?? c.name
        undoTasks[c.id]?.cancel()
        undoTasks[c.id] = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: undoWindow)
            if Task.isCancelled { return }
            let done = await disconnect(c)
            pendingDelete.remove(c.id)
            undoTasks[c.id] = nil
            if !done { host.shell.showToast("\(name) is still connected. Nothing was changed.") }
        }
        host.shell.showToast(
            "\(name) disconnected", lifetime: undoWindow.inSeconds,
            undo: { [weak self] in self?.undoDisconnect(c.id) })
    }

    func undoDisconnect(_ id: Int64) {
        undoTasks[id]?.cancel()
        undoTasks[id] = nil
        pendingDelete.remove(id)
    }
}

extension Duration {
    var inSeconds: TimeInterval { Double(components.seconds) + Double(components.attoseconds) / 1e18 }
}

extension ConnectionsModel {
    /// "Connect another" on the done step: back to the tiles in the same dialog.
    func addAnother() {
        stopFlow()
        add = ConnAddState()
        picks = .idle
        addError = nil
    }
}
