import Admin
// LoreImportModel — the import dialogs of Lore (plan R4-02): "Import from Repo…", "Import Files…", review, commit, Undo
// Import, and the history of earlier imports with resume.
//
// Security model. Everything the Core stages is untrusted text from repos and zips, and the Core (R4-01) is the gate: it
// refuses unsafe paths, binary files and oversized input, and nothing becomes a note before Commit. This side shows only
// counts, titles and paths (as plain `Text`, never as links), sends only what the person picked on this Mac (never a
// walked folder), and leaves out private files (`PreFilter.isRestricted`) and files over 1 MB before they leave the Mac.
// A run is never deleted here: a closed dialog leaves it on the Core, and the history picks it up again.
import AppKit
import CoreKit
import CoreUI
import Foundation
import Observation
import Shell
import UniformTypeIdentifiers

@MainActor @Observable
final class LoreImportModel {
    enum Phase: Equatable {
        case chooser, repoSetup, review, done, undone, history
        /// Words, and how far along (0...1) when the Core can say.
        case working(String, Double?)
        case failed(String)
    }

    let host: any AdminHost
    let service: any LoreImportService
    let projectNames: [String: String]
    var phase = Phase.chooser
    var run: LoreImportRun?
    var items: [LoreImportItem] = []
    var seeThem = false
    /// The project id new notes go to; "" = personal. A repo import needs one.
    var project = ""
    var runs: [LoreImportRun] = []
    var historyLoaded = false
    /// One line under the list: an include or skip the Core did not take.
    var notice: String?
    /// Files left out on this Mac, by reason.
    var leftOut: [String: Int] = [:]

    @ObservationIgnored private var retry: (() -> Void)?
    @ObservationIgnored private var poll: Task<Void, Never>?
    @ObservationIgnored var pause: @Sendable (Int) async -> Void = {
        try? await Task.sleep(for: .seconds(Double(1 << $0)))
    }

    init(host: any AdminHost, service: any LoreImportService, projectNames: [String: String], project: String = "") {
        self.host = host
        self.service = service
        self.projectNames = projectNames
        self.project = project
    }

    var projectOptions: [CoreSelectOption<String>] {
        projectNames.sorted { $0.value.localizedStandardCompare($1.value) == .orderedAscending }
            .map { CoreSelectOption($0.key, $0.value, symbol: "folder") }
    }

    var projectOptionsWithPersonal: [CoreSelectOption<String>] {
        [CoreSelectOption("", "Personal", symbol: "person")] + projectOptions
    }

    var place: String { LoreImportWords.place(project, projectNames) }

    func present() { host.shell.present(ShellDialog(id: "lore-import") { LoreImportView(model: self) }) }
    func close() { host.shell.closeDialog() }

    func words(_ error: any Error) -> String {
        if case .rateLimited(let after)? = CoreError.unwrapping(error) { host.rateLimited(retryAfter: after) }
        return (CoreFailure.of(error) ?? CoreError.unwrapping(error))?.localizedDescription
            ?? error.localizedDescription
    }

    private func fail(_ why: String, retry again: (() -> Void)? = nil) {
        poll?.cancel()
        retry = again
        phase = .failed(why)
    }

    func tryAgain() { retry?() }
    var canTryAgain: Bool { retry != nil }

    /// A dropped link is tried again after 2 s and 4 s; any answer from the Core is final.
    private func retrying<T: Sendable>(_ op: @Sendable () async throws -> T) async throws -> T {
        var attempt = 0
        while true {
            do { return try await op() } catch {
                guard case .offline? = CoreError.unwrapping(error), attempt < 2 else { throw error }
                attempt += 1
                await pause(attempt)
            }
        }
    }

    // MARK: from a repo

    func readRepo() {
        guard !project.isEmpty else { return }
        phase = .working("Reading the docs of \(place)…", nil)
        let again: () -> Void = { [weak self] in self?.readRepo() }
        Task {
            do {
                let r = try await service.startImport(repo: true, project: project)
                if r.state == "abandoned" {
                    fail(r.error ?? "The docs of this project could not be read.", retry: again)
                } else {
                    await review(r)
                }
            } catch { fail(words(error), retry: again) }
        }
    }

    // MARK: from files

    /// Asks which files, then sends them. Cancelling the panel changes nothing.
    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Choose Markdown files or a zip of them"
        panel.prompt = "Import"
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText, .zip]
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        upload(panel.urls)
    }

    func upload(_ urls: [URL]) {
        phase = .working("Reading \(urls.count == 1 ? "1 file" : "\(urls.count) files")…", nil)
        Task {
            let pick = await Task.detached { LoreImportDisk.read(urls) }.value
            leftOut = pick.skipped
            guard !pick.isEmpty else {
                fail("None of the chosen files can be imported. Choose Markdown files (.md) or a zip of them.")
                return
            }
            var id: String?
            do {
                var r = try await service.startImport(repo: false, project: project.isEmpty ? nil : project)
                id = r.id
                let runID = r.id
                for zip in pick.zips {
                    phase = .working("Sending a zip…", nil)
                    r = try await retrying { try await service.addImportZip(runID, zip) }
                }
                let batches = LoreImportDisk.batches(pick.files)
                for (i, batch) in batches.enumerated() {
                    phase = .working(
                        "Sending \(LoreImportWords.notes(pick.files.count))…", Double(i) / Double(max(batches.count, 1))
                    )
                    r = try await retrying { try await service.addImportFiles(runID, batch) }
                }
                r = try await retrying { try await service.finishImport(runID) }
                await review(r)
            } catch {
                // The run stays on the Core in the history only when it can still be used; an upload that broke is dropped.
                if let id { _ = try? await service.abandonImport(id) }
                fail(words(error))
            }
        }
    }

    // MARK: review

    func review(_ r: LoreImportRun) async {
        run = r
        project = r.project ?? ""
        items = []
        notice = nil
        seeThem = false
        phase = .review
        await loadItems(r.id)
    }

    private func loadItems(_ id: String) async {
        var after = 0
        var all: [LoreImportItem] = []
        do {
            // The Core stages at most 2 000 items; 500 a call.
            for _ in 0..<5 {
                let page = try await service.importItems(id, after: after, limit: 500)
                all += page
                guard page.count == 500, let last = page.last else { break }
                after = last.seq
            }
            if run?.id == id { items = all }
        } catch { notice = "Unable to list the notes: \(words(error))" }
    }

    func set(_ item: LoreImportItem, include: Bool) {
        guard let run, phase == .review, !item.locked, let at = items.firstIndex(where: { $0.seq == item.seq }) else {
            return
        }
        items[at].mark = include ? "include" : "skip"
        notice = nil
        Task {
            do { self.run = try await service.markImportItems(run.id, seqs: [item.seq], include: include) } catch {
                if let at = items.firstIndex(where: { $0.seq == item.seq }) { items[at].mark = item.mark }
                notice = "Unable to change that: \(words(error))"
            }
        }
    }

    func setAll(include: Bool) {
        guard let run, phase == .review else { return }
        notice = nil
        Task {
            do {
                self.run = try await service.markImportItems(run.id, seqs: [], include: include)
                await loadItems(run.id)
            } catch { notice = "Unable to change that: \(words(error))" }
        }
    }

    /// New notes go to this project; the Core flags every item again against it.
    func moveAll(to id: String) {
        guard let run, phase == .review else { return }
        project = id
        notice = nil
        Task {
            do {
                self.run = try await service.moveImportItems(run.id, seqs: [], project: id.isEmpty ? nil : id)
                await loadItems(run.id)
            } catch {
                project = self.run?.project ?? ""
                notice = "Unable to move them: \(words(error))"
            }
        }
    }

    func discard() {
        guard let run else { return close() }
        Task {
            do {
                _ = try await service.abandonImport(run.id)
                close()
                host.shell.showToast("Import discarded", kind: .info)
            } catch { notice = "Unable to discard it: \(words(error))" }
        }
    }

    // MARK: commit and undo

    func commit() {
        guard let run else { return }
        let id = run.id
        let total = max(run.include, 1)
        phase = .working("Importing \(LoreImportWords.notes(run.include))…", 0)
        watch(id) { Double($0.handled) / Double(total) }
        Task {
            do {
                let r = try await service.commitImport(id)
                poll?.cancel()
                self.run = r
                phase = .done
                host.shell.showToast(
                    "Imported \(LoreImportWords.notes(r.results["created"] ?? r.handled))", kind: .ok,
                    actionTitle: "Undo Import", undo: { [weak self] in self?.undo() })
            } catch { fail(words(error), retry: { [weak self] in self?.commit() }) }
        }
    }

    func undo() {
        guard let run else { return }
        let id = run.id
        phase = .working("Putting the notes back…", nil)
        Task {
            do {
                let r = try await service.undoImport(id)
                self.run = r
                phase = .undone
                host.shell.showToast("Import undone", kind: .info)
            } catch { fail(words(error), retry: { [weak self] in self?.undo() }) }
        }
    }

    /// Asks the Core how far a commit is, about once a second, while the commit call is still open.
    private func watch(_ id: String, progress: @escaping @Sendable (LoreImportRun) -> Double) {
        poll?.cancel()
        poll = Task { [service] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(900))
                guard !Task.isCancelled, let r = try? await service.importRun(id) else { continue }
                if case .working(let text, _) = phase { phase = .working(text, progress(r)) }
            }
        }
    }

    // MARK: history

    func openHistory() {
        phase = .history
        Task {
            do {
                runs = try await service.importRuns()
                historyLoaded = true
            } catch { fail(words(error), retry: { [weak self] in self?.openHistory() }) }
        }
    }

    /// A click on an earlier import: it goes on from where it stopped.
    func resume(_ r: LoreImportRun) {
        switch r.state {
        case "staging":
            phase = .working("Finishing the import…", nil)
            Task {
                do { await review(try await service.finishImport(r.id)) } catch {
                    fail(words(error), retry: { [weak self] in self?.resume(r) })
                }
            }
        case "review": Task { await review(r) }
        case "committing":
            run = r
            commit()
        case "committed":
            run = r
            project = r.project ?? ""
            phase = .done
        case "undoing":
            run = r
            undo()
        default: break
        }
    }
}
