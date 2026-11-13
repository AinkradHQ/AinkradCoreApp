import BrainImport
import Foundation
import Testing

@testable import Admin
@testable import Brain
@testable import Shell

private func root() throws -> URL {
    let r = FileManager.default.temporaryDirectory.appendingPathComponent("places-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: r, withIntermediateDirectories: true)
    return r.resolvingSymlinksInPath()
}

private func put(_ root: URL, _ rel: String, _ text: String = "# x\nbody") throws {
    let url = root.appendingPathComponent(rel)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try text.write(to: url, atomically: true, encoding: .utf8)
}

private func found(_ kind: PlacesSource.Kind, _ places: ImportPlaces, home: URL? = nil) async -> CollectReport {
    await PlacesSource(kind, places: places, device: "t", home: home ?? URL(fileURLWithPath: "/nowhere")).scan()
}

@Suite struct ImportPlacesTests {
    @Test func aFreshInstallReadsNothing() async {
        let p = ImportPlaces()
        #expect(p.folders.isEmpty && p.mode == .folders && p.chat == nil && p.disk == nil)
        for k in [PlacesSource.Kind.doc, .vault, .agents, .chat] { #expect(await found(k, p).found == 0) }
    }

    @Test func choicesAreKeptPerMac() throws {
        let name = "places-test-\(UUID().uuidString)"
        let d = try #require(UserDefaults(suiteName: name))
        defer { d.removePersistentDomain(forName: name) }
        let a = ImportPlaces(defaults: d)
        a.folders = [URL(fileURLWithPath: "/a/b")]
        a.mode = .disk
        a.chat = URL(fileURLWithPath: "/c")
        let b = ImportPlaces(defaults: d)
        #expect(b.folders.map(\.path) == ["/a/b"] && b.mode == .disk && b.chat?.path == "/c")
    }

    @Test func chosenFoldersAreScannedWithTheExistingCollectors() async throws {
        let projects = try root()  // a folder of projects
        try put(projects, "Shop/Docs/plan.md")
        try put(projects, "Shop/Docs/Contracts/deal.md")
        try put(projects, "Shop/CLAUDE.md")
        try put(projects, "Shop/Repositories/api/AGENTS.md")
        try put(projects, "GitScope/Docs/old.md")
        let oneProject = try root()  // a folder that is itself a project
        try put(oneProject, "Docs/spec.md")
        try put(oneProject, "AGENTS.md")
        let vault = try root()
        try put(vault, ".obsidian/app.json", "{}")
        try put(vault, "Ideas/a.md")
        try put(vault, "b.md")
        let plain = try root()  // not a vault: no notes from it
        try put(plain, "c.md")

        let p = ImportPlaces(folders: [projects, oneProject, vault, plain])
        let docs = await found(.doc, p)
        #expect(docs.found == 4)  // plan, deal, old, spec
        #expect(docs.skipped["restricted"] == 1 && docs.skipped["deprecated:GitScope"] == 1)
        #expect(await found(.vault, p).found == 2)
        #expect(await found(.agents, p).found == 3)  // CLAUDE.md, AGENTS.md, the project's own AGENTS.md
    }

    @Test func theSameFolderChosenTwiceIsOneSource() async throws {
        let r = try root()
        try put(r, "A/Docs/x.md")
        let p = ImportPlaces(folders: [r, r])
        #expect(await found(.doc, p).found == 1)
    }

    @Test func chatExportsComeFromTheChosenFolderOnly() async throws {
        let r = try root()
        try put(r, "export.zip", "x")
        #expect(await found(.chat, ImportPlaces()).found == 0)
        #expect(await found(.chat, ImportPlaces(chat: r)).found >= 1)
    }

    @Test func wholeDiskReadsWhatTheSearchFound() async throws {
        let home = try root()
        try put(home, "Work/shop/Docs/plan.md")
        try put(home, "Work/shop/README.md")
        try put(home, "Work/shop/Docs/Contracts/c.md")
        try put(home, "Notes/.obsidian/x.json", "{}")
        try put(home, "Notes/n.md")
        try put(home, "Library/Docs/skip.md")
        let p = ImportPlaces(mode: .disk, folders: [try root()], home: home)
        #expect(await found(.doc, p, home: home).found == 0)  // nothing is read before the search
        let f = p.runSearch { _ in }
        #expect(f.docFolders.count == 1 && f.vaults.count == 1 && f.agentFiles.count == 1)
        let docs = await found(.doc, p, home: home)
        #expect(docs.found == 2 && docs.skipped["restricted"] == 1)
        #expect(await found(.vault, p, home: home).found == 1)
        #expect(await found(.agents, p, home: home).found == 1)
    }

    @Test func theSearchAnswerSurvivesARestartSoASyncDoesNotWalkAgain() throws {
        let home = try root()
        try put(home, "w/Docs/a.md")
        let file = home.appendingPathComponent("state/disk.json")
        let a = ImportPlaces(diskFile: file, mode: .disk, home: home)
        _ = a.runSearch { _ in }
        let b = ImportPlaces(diskFile: file, mode: .disk, home: home)
        #expect(b.disk?.docFolders.count == 1)
    }

    @Test func suggestionsAreProjectLookingFoldersNeverTheProtectedOnes() throws {
        let home = try root()
        try put(home, "Code/site-a/.git/HEAD")
        try put(home, "Code/site-b/.git/HEAD")
        try put(home, "Studio/Docs/a.md")
        try put(home, "Vault/.obsidian/app.json", "{}")
        try put(home, "Plain/readme.txt")
        try put(home, "Documents/Work/Docs/secret.md")  // would ask macOS for access: never opened
        try put(home, "Library/Docs/x.md")
        try put(home, ".hidden/Docs/y.md")
        try put(home, "Work/node_modules/Docs/z.md")
        let all = ImportPlaces.suggestions(home: home, exclude: [], limit: 10).map(\.lastPathComponent)
        #expect(all == ["Code", "Studio", "Vault", "Work"].filter { $0 != "Work" })
        #expect(ImportPlaces.suggestions(home: home, exclude: [], limit: 2).count == 2)
        let left = ImportPlaces.suggestions(home: home, exclude: [URL(fileURLWithPath: home.path + "/Code")], limit: 10)
        #expect(left.map(\.lastPathComponent) == ["Studio", "Vault"], "\(left.map(\.path))")
    }
}

@MainActor
struct ImportWhereModelTests {
    private func model(_ p: ImportPlaces, home: URL) -> ImportModel {
        ImportModel(
            host: FakeHost(), routes: BrainRoutes(transport: FakeBrainTransport()),
            sources: [
                PlacesSource(.doc, places: p, device: "t", home: home),
                PlacesSource(.agents, places: p, device: "t", home: home),
            ], places: p)
    }

    private func settle(_ m: ImportModel) async {
        await m.settled()
    }

    @Test func addingAndRemovingAFolderRecountsTheSources() async throws {
        let home = try root()
        let folder = try root()
        try put(folder, "A/Docs/x.md")
        let p = ImportPlaces(suggest: { _ in [] })
        let m = model(p, home: home)
        await m.scan()
        #expect(m.folders.isEmpty && m.choices.first { $0.id == "doc" }?.found == 0)
        m.addFolders([folder, folder])
        await settle(m)
        #expect(m.folders.count == 1 && p.folders.count == 1)
        #expect(m.choices.first { $0.id == "doc" }?.found == 1)
        m.removeFolder(folder)
        await settle(m)
        #expect(m.choices.first { $0.id == "doc" }?.found == 0 && p.folders.isEmpty)
    }

    @Test func aSuggestionIsOfferedNotAdded() async throws {
        let s = URL(fileURLWithPath: "/sample/Studio")
        let p = ImportPlaces(suggest: { taken in taken.isEmpty ? [s] : [] })
        let m = model(p, home: try root())
        await m.scan()
        #expect(m.suggestions == [s] && m.folders.isEmpty && p.folders.isEmpty)
        m.addFolders([s])
        #expect(m.suggestions.isEmpty && m.folders == [s])
    }

    @Test func theWholeDiskModeSearchesShowsACountAndFillsTheSources() async throws {
        let home = try root()
        try put(home, "w/Docs/a.md")
        try put(home, "w/README.md")
        let p = ImportPlaces(mode: .disk, home: home)
        let m = model(p, home: home)
        await m.scan()
        #expect(m.mode == .disk && !m.searching)
        #expect(m.searched?.stopped == nil && (m.searched?.checked ?? 0) >= 3)
        #expect(m.choices.first { $0.id == "doc" }?.found == 1)
        #expect(m.choices.first { $0.id == "agents_md" }?.found == 1)
    }

    @Test func stoppingASearchKeepsWhatItFound() async throws {
        let p = ImportPlaces(
            mode: .disk,
            search: { progress in
                var f = DocWalker.Found()
                f.docFolders = ["/nowhere/Docs"]
                while !Task.isCancelled {
                    progress(1240)
                    Thread.sleep(forTimeInterval: 0.005)
                }
                f.checked = 1240
                f.stopped = "cancelled"
                return f
            })
        let m = model(p, home: try root())
        let scan = Task { await m.scan() }
        for _ in 0..<200 where m.checked == 0 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(m.searching && m.checked == 1240 && !m.canStart)
        m.stopSearch()
        await scan.value
        #expect(!m.searching && m.searched?.stopped == "cancelled" && p.disk?.checked == 1240)
        #expect(WhereWords.searched(try #require(m.searched)) == "Stopped at 1,240 files.")
    }

    @Test func switchingModeCancelsTheSearchAndGoesBackToFolders() async throws {
        let p = ImportPlaces(
            mode: .disk,
            search: { _ in
                while !Task.isCancelled { Thread.sleep(forTimeInterval: 0.005) }
                var f = DocWalker.Found()
                f.stopped = "cancelled"
                return f
            })
        let m = model(p, home: try root())
        let scan = Task { await m.scan() }
        for _ in 0..<200 where !m.searching { try await Task.sleep(for: .milliseconds(10)) }
        m.setMode(.folders)
        await scan.value
        await settle(m)
        #expect(m.mode == .folders && p.mode == .folders && !m.searching)
    }

    @Test func aFolderMacOSRefusesIsCountedAsNotAllowed() async throws {
        let locked = try root()
        try put(locked, "A/Docs/x.md")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
        let gone = URL(fileURLWithPath: "/sample/missing")
        let p = ImportPlaces(folders: [locked, gone], suggest: { _ in [] })
        let m = model(p, home: try root())
        await m.scan()
        #expect(m.notAllowed == 1)  // a folder that is gone is not a privacy problem
        #expect(WhereWords.notAllowed(1).hasSuffix("Privacy & Security."))
    }
}
