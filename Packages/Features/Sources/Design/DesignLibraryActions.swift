import Admin
import AppKit
import CoreKit
import CoreUI
import Foundation
import Projects
import Shell
import SwiftUI

/// The library's actions on the model: card clicks with ⌘ and ⇧, favourites, restore, undoable delete, bulk moves, copies,
/// export, the AI control, the design-system link and brand kit edits. Each says in words what happened or why not.
enum AIAction { case pause, takeOver, resume }

/// A flag Undo can set from the toast while the delay runs.
@MainActor private final class Cancel { var on = false }

extension DesignModel {
    /// Runs a write: refuses when read-only or paused, words the failure, nil on success.
    func write(_ work: (any DesignService) async throws -> Void) async -> String? {
        guard let service else { return "Not connected to a Core." }
        if readOnly { return "This device can look at designs but not change them." }
        if let why = host.pausedReason { return why }
        do {
            try await work(service)
            return nil
        } catch {
            if CoreError.unwrapping(error) == .forbiddenScope { readOnly = true }
            return words(error)
        }
    }

    private func toastFailure(_ why: String?) -> Bool {
        guard let why else { return false }
        host.shell.showToast(why, kind: .warn)
        return true
    }

    // MARK: clicks and selection

    /// A card was clicked: ⌘ adds or removes it from the selection, ⇧ extends it, a plain click opens it (or, with a
    /// selection showing, ends it). An archived design only selects: it cannot be opened.
    func cardTap(_ item: DesignItem) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            lib.toggle(item.id)
        } else if flags.contains(.shift) {
            lib.extend(to: item.id, in: shown.map(\.id))
        } else if !lib.multi.isEmpty {
            lib.clearSelection()
        } else {
            selected = item.id
            if category == .archived {
                host.shell.showToast(
                    lib.restoreSupported
                        ? "Restore it to open it again."
                        : "Restoring needs a Core update; archived designs are read-only.")
                return
            }
            openItem(item.id)
        }
    }

    /// The items a card's menu acts on: the whole selection when the card is in it, else the card.
    func targets(_ item: DesignItem) -> [DesignItem] {
        lib.multi.contains(item.id) && lib.multi.count > 1 ? items.filter { lib.multi.contains($0.id) } : [item]
    }

    func selectAll() { lib.multi = Set(shown.map(\.id)) }

    // MARK: restore

    func restore(_ doc: DesignDoc) async {
        guard lib.restoreSupported else {
            host.shell.showToast("Restoring needs a Core update.", kind: .warn)
            return
        }
        let why = await write { try await $0.unarchive(doc: doc.id) }
        if toastFailure(why) { return }
        lib.dropArchived(doc.id)
        await reload()
        host.shell.showToast("\(doc.name) is back")
    }

    // MARK: delete with Undo

    /// After the dialog's Delete. Designs the Core can restore are archived at once and Undo restores them; anything else
    /// waits 5 seconds before it goes, hidden meanwhile, and Undo cancels it. Nil on success.
    func removeUndoable(_ list: [DesignItem]) async -> String? {
        guard service != nil, !list.isEmpty else { return "Nothing to delete." }
        if let why = host.pausedReason { return why }
        let what = list.count == 1 ? list[0].name : "\(list.count) items"
        let docs = list.compactMap { i -> DesignDoc? in if case .doc(let d) = i { d } else { nil } }
        if lib.restoreSupported, docs.count == list.count {
            do {
                try await host.elevated("Delete \(what).", done: "deleted", keepsEdit: false) {
                    for d in docs { try await service?.remove(.doc(d)) }
                }
            } catch is AdminDeclined {
                return "Not deleted: Touch ID was not confirmed."
            } catch {
                return words(error)
            }
            finishDelete(list)
            await reload()
            host.shell.showToast("\(what) deleted", actionTitle: "Undo", lifetime: 8) { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    for d in docs { _ = await self.write { try await $0.unarchive(doc: d.id) } }
                    await self.reload()
                    self.host.shell.showToast("\(what) is back")
                }
            }
            return nil
        }
        let ids = list.map(\.id)
        finishDelete(list)
        lib.hide(ids)
        let cancel = Cancel()
        host.shell.showToast("Deleting \(what)…", actionTitle: "Undo", lifetime: 5) { [weak self] in
            cancel.on = true
            self?.lib.unhide(ids)
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5.2))
            guard let self, !cancel.on else { return }
            do {
                try await host.elevated("Delete \(what).", done: "deleted", keepsEdit: false) {
                    for i in list { try await service?.remove(i) }
                }
                lib.unhide(ids)
                await reload()
            } catch {
                lib.unhide(ids)
                host.shell.showToast(
                    error is AdminDeclined ? "Not deleted: Touch ID was not confirmed." : words(error), kind: .warn)
            }
        }
        return nil
    }

    private func finishDelete(_ list: [DesignItem]) {
        host.shell.closeDialog()
        if let o = openID, list.contains(where: { $0.id == o }) { closeItem() }
        lib.multi.subtract(list.map(\.id))
        if let s = selected, list.contains(where: { $0.id == s }) { selected = nil }
    }

    func askDelete(_ list: [DesignItem]) {
        guard !readOnly else {
            return host.shell.showToast("This device can look at designs but not change them.", kind: .warn)
        }
        if list.count == 1 { return askDelete(list[0]) }
        host.shell.present(ShellDialog(id: "design-delete") { DeleteDesignView(model: self, items: list) })
    }

    // MARK: bulk

    /// Relates every item to `project` and ends its other relations: a move.
    func move(_ list: [DesignItem], to project: ProjectRef) async {
        let why = await write { s in
            for i in list {
                for other in i.projects where other != project.id { try await s.link(i, project: other, false) }
                if !i.projects.contains(project.id) { try await s.link(i, project: project.id, true) }
            }
        }
        await reload()
        host.shell.showToast(
            why ?? "\(Words.count(list.count, "item")) moved to \(project.name)", kind: why == nil ? .ok : .warn)
    }

    /// Puts library files into a brand kit or folder.
    func add(_ list: [DesignItem], to kit: BrandKit) async {
        let files = list.compactMap { i -> DesignAsset? in if case .asset(let a) = i { a } else { nil } }
        guard !files.isEmpty else {
            return host.shell.showToast("Only library files go into a kit. Pick some files.", kind: .warn)
        }
        let why = await write { s in
            for a in files where !kit.items.contains(where: { $0.sha == a.sha }) {
                try await s.putKitItem(id: kit.id, sha: a.sha, role: nil)
            }
        }
        await reload()
        host.shell.showToast(
            why ?? "\(Words.count(files.count, "file")) added to \(kit.name)", kind: why == nil ? .ok : .warn)
    }

    // MARK: copies

    /// Copy a design (its layers, as the open canvas has them) or a kit. A library file is stored once by its bytes, so the
    /// Core would answer with the same file: it has no copy.
    func duplicate(_ item: DesignItem) async {
        switch item {
        case .doc(let d) where d.kind == .design: await duplicateDesign(d)
        case .kit(let k):
            let why = await write { s in
                let made = try await s.createCollection(
                    kind: k.kind, name: String("\(k.name) copy".prefix(100)), colors: k.colors, fonts: k.fonts,
                    project: k.projects.first)
                for i in k.items { try await s.putKitItem(id: made.id, sha: i.sha, role: i.role) }
            }
            await reload()
            host.shell.showToast(why ?? "\(k.name) copied", kind: why == nil ? .ok : .warn)
        default:
            host.shell.showToast("This kind cannot be copied.", kind: .warn)
        }
    }

    private func duplicateDesign(_ d: DesignDoc) async {
        guard !readOnly, host.pausedReason == nil else {
            return host.shell.showToast("This device can look at designs but not change them.", kind: .warn)
        }
        let id = DesignItem.doc(d).id
        let wasOpen = openID == id
        if !wasOpen { openItem(id) }
        var editor: DesignEditor?
        // The copy is made from the canvas, so the design is opened and given a moment to load.
        for _ in 0..<60 {
            if let e = editors[d.id], e.attached, e.loaded, !e.layers.layers.isEmpty {
                editor = e
                break
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
        guard let e = editor else {
            if !wasOpen { closeItem() }
            return host.shell.showToast(
                "The design did not open in time to copy it. Open it and try again.", kind: .warn)
        }
        let ops = DesignDuplicate.ops(layers: e.layers) { e.node(of: $0) }
        guard !ops.isEmpty, ops.count <= DesignDuplicate.limit else {
            return host.shell.showToast(
                "This design has too many layers to copy in one step (\(DesignDuplicate.limit) at most).", kind: .warn)
        }
        let why = await create(
            kind: .design, name: String("\(d.name) copy".prefix(100)), project: d.projects.first, system: d.system,
            starter: ops, toast: false)
        if let why { host.shell.showToast(why, kind: .warn) }
    }

    // MARK: export

    /// Saves library files as they are (SVG, PDF, PNG…). One file asks where; several ask for a folder.
    func export(_ list: [DesignItem]) async {
        let files = list.compactMap { i -> DesignAsset? in
            if case .asset(let a) = i, a.check == .ok, a.kind != .font { a } else { nil }
        }
        guard !files.isEmpty, let service else {
            return host.shell.showToast("Only checked library files can be exported.", kind: .warn)
        }
        var dir: URL
        var single: URL?
        if files.count == 1 {
            let p = NSSavePanel()
            p.nameFieldStringValue = files[0].fileName
            guard p.runModal() == .OK, let u = p.url else { return }
            single = u
            dir = u.deletingLastPathComponent()
        } else {
            let p = NSOpenPanel()
            p.canChooseDirectories = true
            p.canChooseFiles = false
            p.canCreateDirectories = true
            p.prompt = "Export here"
            guard p.runModal() == .OK, let u = p.url else { return }
            dir = u
        }
        var done = 0
        for a in files {
            do {
                let data = try await service.data(a.sha)
                let url = single ?? Self.free(dir.appendingPathComponent(a.fileName))
                try data.write(to: url)
                done += 1
            } catch {
                host.shell.showToast("\(a.name) was not exported: \(words(error))", kind: .warn)
            }
        }
        if done > 0 { host.shell.showToast("\(Words.count(done, "file")) exported") }
    }

    /// `name.png` → `name 2.png` when the name is taken.
    nonisolated static func free(_ url: URL) -> URL {
        var n = 1
        var out = url
        while FileManager.default.fileExists(atPath: out.path) {
            n += 1
            let base = url.deletingPathExtension().lastPathComponent
            out = url.deletingLastPathComponent().appendingPathComponent("\(base) \(n)")
                .appendingPathExtension(url.pathExtension)
        }
        return out
    }

    // MARK: AI and system

    func setAI(_ d: DesignDoc, _ action: AIAction) async {
        var made: DesignDoc?
        let why = await write { s in
            switch action {
            case .pause: made = try await s.pauseAI(doc: d.id)
            case .takeOver: made = try await s.takeOver(doc: d.id)
            case .resume: made = try await s.resumeAI(doc: d.id)
            }
        }
        if let made, let i = docs.firstIndex(where: { $0.id == d.id }) { docs[i].aiPaused = made.aiPaused }
        let ok: String =
            switch action {
            case .pause: "AI is paused on \(d.name). It cannot change it until you resume."
            case .takeOver: "You have \(d.name). AI waits until you resume it."
            case .resume: "AI may draw on \(d.name) again."
            }
        host.shell.showToast(why ?? ok, kind: why == nil ? .ok : .warn)
    }

    /// Links a design to a design system, or ends the link (`nil`).
    func setSystem(_ d: DesignDoc, _ system: String?) async {
        var made: DesignDoc?
        let why = await write { made = try await $0.setSystem(doc: d.id, system: system) }
        if let why { return host.shell.showToast(why, kind: .warn) }
        if let i = docs.firstIndex(where: { $0.id == d.id }) { docs[i].system = made?.system ?? system }
        host.shell.showToast(system == nil ? "\(d.name) is not linked to a system" : "\(d.name) now follows the system")
    }

    // MARK: kits

    func createKit(_ kind: BrandKit.Kind, name: String) async -> String? {
        var made: BrandKit?
        let why = await write {
            made = try await $0.createCollection(kind: kind, name: name, colors: [], fonts: [], project: self.project)
        }
        await reload()
        if why == nil, let made {
            category = kind == .folder ? .folders : .brand
            openItem(DesignItem.kit(made).id)
        }
        return why
    }

    /// Edits a kit; its colours and fonts replace the whole list. Nil on success.
    func editKit(_ kit: BrandKit, colors: [String]? = nil, fonts: [String]? = nil) async -> String? {
        var made: BrandKit?
        let why = await write { made = try await $0.patchKit(id: kit.id, name: nil, colors: colors, fonts: fonts) }
        if let made, let i = kits.firstIndex(where: { $0.id == kit.id }) { kits[i] = made } else { await reload() }
        return why
    }

    func putKitItem(_ kit: BrandKit, sha: String, role: String?) async -> String? {
        let why = await write { try await $0.putKitItem(id: kit.id, sha: sha, role: role) }
        await reload()
        return why
    }

    func removeKitItem(_ kit: BrandKit, sha: String) async -> String? {
        let why = await write { try await $0.removeKitItem(id: kit.id, sha: sha) }
        await reload()
        return why
    }

    /// Writes new tags on a library file.
    func setTags(_ a: DesignAsset, _ tags: [String]) async -> String? {
        var made: DesignAsset?
        let why = await write { made = try await $0.setTags(sha: a.sha, tags: tags) }
        if let made, let i = assets.firstIndex(where: { $0.sha == a.sha }) { assets[i] = made }
        return why
    }
}

/// A design's layers as the add ops that rebuild them in a new design: parents before children, in sibling order.
enum DesignDuplicate {
    /// The most ops one Core batch takes.
    static let limit = 200

    static func ops(layers: LayerTree, node: (String) -> EditorNode?) -> [[String: DJSON]] {
        var out: [[String: DJSON]] = []
        func walk(_ l: DesignLayer) {
            let n = node(l.id)
            var op: [String: DJSON] = [
                "op": .string("add"), "id": .string(l.id), "type": .string(l.type),
                "parent": l.parent.map(DJSON.string) ?? .null, "order": .string(l.order),
                "name": .string(n?.name ?? l.name),
            ]
            if let p = n?.props, !p.isEmpty { op["props"] = .object(p) }
            if let t = n?.text { op["text"] = .string(t) }
            out.append(op)
            for c in layers.children(of: l.id) { walk(c) }
        }
        for r in layers.children(of: nil) { walk(r) }
        return out
    }
}
