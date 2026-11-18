import Admin
import CoreKit
import Foundation
import Observation

/// What the Run page of one project holds: the newest run spec (and the version before it, for See Changes and Undo), the
/// secrets by name, the run's state, and the writes. Reads go through `ProjectsModel.runService`; every write runs behind the
/// host's Touch ID. A secret's value is passed straight to the service and kept nowhere.
@MainActor @Observable
final class RunPageModel {
    let model: ProjectsModel
    let projectID: Int64

    private(set) var spec: SpecVersionItem?
    /// The version before `spec`, when there is one.
    private(set) var previous: SpecVersionItem?
    private(set) var secrets: [SecretItem] = []
    private(set) var status: RunStatus?
    /// What the live run reports of each service, and its newest log lines (the last 500).
    private(set) var services: [ProjectLive.Service] = []
    private(set) var logLines: [ProjectLive.LogLine] = []
    private var logNext = 0
    private(set) var loaded = false
    /// Why the first read failed, in words.
    private(set) var loadError: String?
    private(set) var busy = false
    /// A refusal for the write in flight, shown in its sheet.
    private(set) var writeError: String?
    /// The log filter: a service name, nil for all.
    var logService: String?

    init(model: ProjectsModel, projectID: Int64) {
        self.model = model
        self.projectID = projectID
    }

    private var service: (any ProjectRunService)? { model.runService }

    // MARK: derived

    /// One secret line: every secret the spec refers to, set or not, then the stored ones it does not refer to.
    struct SecretRow: Identifiable, Equatable {
        let name: String
        let item: SecretItem?
        var id: String { name }
    }

    var secretRows: [SecretRow] {
        let stored = Dictionary(uniqueKeysWithValues: secrets.map { ($0.name, $0) })
        let wanted = spec?.secretNames ?? []
        let extra = secrets.map(\.name).filter { !wanted.contains($0) }.sorted()
        return (wanted + extra).map { SecretRow(name: $0, item: stored[$0]) }
    }

    var missingSecrets: [String] { secretRows.filter { $0.item == nil }.map(\.name) }

    /// The draft line shows while the newest version came from a converter.
    var drafted: Bool { spec?.drafted == true }

    // MARK: reads

    func load() async {
        guard let service else { return }
        do {
            spec = try await service.spec(project: projectID)
            secrets = try await service.secrets(project: projectID)
            status = try await service.run(project: projectID)
            await observe(service)
            previous = try await earlier(service)
            loadError = nil
        } catch {
            if !loaded { loadError = words(error) }
        }
        loaded = true
    }

    private func earlier(_ service: any ProjectRunService) async throws -> SpecVersionItem? {
        guard let v = spec?.version, v > 1 else { return nil }
        return try await service.specVersion(project: projectID, v - 1)
    }

    /// Every minute while the page is open: a viewer on the Run page keeps a running project from idling out, then the run, its
    /// services and its logs are read again. Ends when the view goes away (the task is cancelled).
    func watch() async {
        await load()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled, let service else { continue }
            if status?.state == "running" { try? await service.touch(project: projectID) }
            if let s = try? await service.run(project: projectID) { status = s }
            await observe(service)
        }
    }

    /// Services and log lines of the live run; both empty once it is over.
    private func observe(_ service: any ProjectRunService) async {
        guard status?.state == "running" || status?.state == "starting" else {
            services = []
            return
        }
        if let s = try? await service.services(project: projectID) { services = s }
        if let page = try? await service.logs(project: projectID, after: logNext) {
            logNext = page.next
            logLines = Array((logLines + page.lines).suffix(500))
        }
    }

    // MARK: writes

    /// Saves `json` as the next version. False leaves the sheet open with `writeError`.
    @discardableResult
    func saveSpec(_ json: String, origin: String = "manual", reason: String, done: String) async -> Bool {
        await write(reason) { service in
            _ = try await service.saveSpec(project: self.projectID, json: json, origin: origin)
        } then: {
            await self.load()
            self.model.host.shell.showToast(done)
        }
    }

    /// Undo on the draft line: the version before the draft becomes the newest again (a new version, so nothing is lost).
    @discardableResult
    func undoDraft(_ projectName: String) async -> Bool {
        guard let previous else { return false }
        return await saveSpec(
            previous.json, reason: "Go back to the setup of \(projectName) from before the draft.",
            done: "Draft undone")
    }

    /// Drafts the setup from the primary repo's compose file, run.sh, Makefile or package.json (never run, only read).
    @discardableResult
    func draftFromRepo(image: String, projectName: String) async -> Bool {
        await write("Draft the setup of \(projectName) from its repo.") { service in
            _ = try await service.draft(project: self.projectID, image: image)
        } then: {
            await self.load()
            self.model.host.shell.showToast("Setup drafted")
        }
    }

    @discardableResult
    func setSecret(name: String, value: String, replacing: Bool, projectName: String) async -> Bool {
        await write("\(replacing ? "Replace" : "Set") the secret \(name) of \(projectName).") { service in
            try await service.setSecret(project: self.projectID, name: name, value: value)
        } then: {
            await self.load()
            self.model.host.shell.showToast(replacing ? "\(name) replaced" : "\(name) set")
        }
    }

    func clearWriteError() { writeError = nil }

    private func write(
        _ reason: String, _ op: @escaping (any ProjectRunService) async throws -> Void,
        then: () async -> Void
    ) async -> Bool {
        guard let service, !busy, model.mayWrite() else { return false }
        busy = true
        writeError = nil
        defer { busy = false }
        do {
            try await model.host.elevated(reason, done: "saved", keepsEdit: true) { try await op(service) }
        } catch is AdminDeclined {
            return false
        } catch {
            writeError = words(error)
            return false
        }
        await then()
        return true
    }

    private func words(_ error: any Error) -> String {
        if let f = error as? RunFailure { return f.sentence }
        return model.words(error)
    }
}
