import AppKit
import Foundation

/// The Keys panel's state: the list order, the open row, the inline forms, copying.
extension LeylineModel {
    /// Newest first, so a key just made or imported is at the top.
    var keyList: [KeyItem] {
        keys.enumerated().sorted { a, b in
            switch (a.element.createdAt, b.element.createdAt) {
            case (let x?, let y?) where x != y: x > y
            case (.some, nil): true
            case (nil, .some): false
            default: a.offset < b.offset
            }
        }.map(\.element)
    }

    /// The names taken, for the forms' defaults.
    var keyNames: [String] { keys.map(\.name) }

    /// Opens the panel on a form (⌘G, ⌘I, the tiles, the launcher), or closes the form that is open.
    func openKeyForm(_ form: KeyForm) {
        keysOpen = true
        if keyForm == form { return closeKeyForm() }
        clearWriteError()
        keyDraft = KeyDraft()
        keyDraft.name = form == .generate ? KeyText.uniqueName(keyNames) : ""
        keyForm = form
    }

    /// Esc with no form open, the panel's esc: the panel goes, and any form with it.
    func closeKeys() {
        keysOpen = false
        closeKeyForm()
    }

    /// Esc on a form: the form goes, with the key text and passphrase it held.
    func closeKeyForm() {
        keyForm = nil
        keyDraft = KeyDraft()
        clearWriteError()
    }

    /// A key file dropped on the panel or chosen in Import: Import opens with it.
    func importKeyFile(_ url: URL) {
        guard let text = DropZone.text(url) else {
            host.shell.showToast("That file is not a key (too big, or not text).", kind: .warn)
            return
        }
        if keyForm != .importing { openKeyForm(.importing) }
        clearWriteError()
        keyDraft.load(file: url.lastPathComponent, text: text, taken: keyNames)
    }

    /// ↑ ↓ in the panel: the next key in the list opens, the others close.
    func moveKey(down: Bool) {
        let ids = keyList.map(\.id)
        guard !ids.isEmpty else { return }
        let at = keySelected.flatMap { ids.firstIndex(of: $0) }
        keySelected = ids[down ? min((at ?? -1) + 1, ids.count - 1) : max((at ?? ids.count) - 1, 0)]
    }

    /// ⌘C, and the row's Copy Public Key.
    func copyPublicKey(_ key: KeyItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(key.publicKey, forType: .string)
        host.shell.showToast("Public key of \(key.name) copied")
    }

    /// After a key is made or imported: the form closes, the key opens at the top and is lit for a moment.
    func keyMade(_ id: String) {
        keyForm = nil
        keyDraft = KeyDraft()
        keySelected = id
        keyFresh = id
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            if self?.keyFresh == id { self?.keyFresh = nil }
        }
    }

    /// A known host's Review: the host's Access, where its pinned key is.
    func reviewHostKey(_ known: KnownHostItem) {
        guard let h = hosts.first(where: { $0.name == known.host || $0.id == known.host }) else { return }
        openHost(h.id, .access)
    }
}
