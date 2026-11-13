import Foundation
import Testing

@testable import BrainImport

@Suite struct DocWalkerTests {
    static func names(_ paths: [String], under root: URL) -> [String] {
        paths.map { $0.components(separatedBy: root.lastPathComponent + "/").last ?? $0 }.sorted()
    }

    @Test func findsDocsReadmesAgentFilesAndVaultsAndSkipsTheRest() throws {
        let root = try fixtureRoot()
        try write(root, "Work/shop/Docs/plan.md", "# plan")
        try write(root, "Work/blog/docs/guide/a.md", "# a")
        try write(root, "Work/shop/README.md", "# shop")
        try write(root, "Work/shop/CLAUDE.md", "x")
        try write(root, "Work/shop/GEMINI.md", "x")
        try write(root, "Work/shop/MEMORY.md", "x")
        try write(root, "Work/shop/AGENTS.md", "x")
        try write(root, "Work/shop/notes.md", "loose notes are not docs")
        try write(root, "Notes/vault/.obsidian/app.json", "{}")
        try write(root, "Notes/vault/Ideas/idea.md", "# idea")
        // Everything below must be left alone.
        try write(root, "Library/Caches/Docs/x.md", "no")
        try write(root, "Work/app/node_modules/pkg/README.md", "no")
        try write(root, "Work/app/node_modules/pkg/Docs/d.md", "no")
        try write(root, "Work/app/build/README.md", "no")
        try write(root, "Work/app/DerivedData/README.md", "no")
        try write(root, "Work/app/.build/README.md", "no")
        try write(root, "Work/app/dist/README.md", "no")
        try write(root, "Work/app/target/README.md", "no")
        try write(root, "Work/app/vendor/README.md", "no")
        try write(root, "Work/app/Pods/README.md", "no")
        try write(root, "Work/app/.git/README.md", "no")
        try write(root, ".hidden/Docs/h.md", "no")
        try write(root, ".Trash/README.md", "no")

        let f = DocWalker().walk(root: root)
        #expect(f.stopped == nil)
        #expect(Self.names(f.docFolders, under: root) == ["Work/blog/docs", "Work/shop/Docs"])
        #expect(Self.names(f.vaults, under: root) == ["Notes/vault"])
        #expect(
            Self.names(f.agentFiles, under: root)
                == [
                    "Work/shop/AGENTS.md", "Work/shop/CLAUDE.md", "Work/shop/GEMINI.md", "Work/shop/MEMORY.md",
                    "Work/shop/README.md",
                ])
        let files = DocWalker.files(of: f)
        #expect(files.docs.count == 2 && files.vault.count == 1 && files.agents.count == 5)
        #expect(files.vault[0].lastPathComponent == "idea.md")
    }

    @Test func aFolderMacOSRefusesIsCountedNotFatal() throws {
        let root = try fixtureRoot()
        try write(root, "ok/Docs/a.md", "# a")
        try write(root, "locked/Docs/b.md", "# b")
        let locked = root.appendingPathComponent("locked")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
        let f = DocWalker().walk(root: root)
        #expect(f.unreadable == 1)
        #expect(f.docFolders.count == 1)
    }

    @Test func theFileCapStopsTheWalkAndSaysSo() throws {
        let root = try fixtureRoot()
        for i in 0..<30 { try write(root, "d\(i)/README.md", "x") }
        let f = DocWalker(limits: .init(maxChecked: 20)).walk(root: root)
        #expect(f.stopped == "files" && f.checked == 20)
        #expect(f.agentFiles.count < 30)
    }

    @Test func theTimeCapStopsTheWalk() throws {
        let root = try fixtureRoot()
        for i in 0..<1200 { try write(root, "d\(i / 100)/f\(i).txt", "x") }
        let f = DocWalker(limits: .init(seconds: -1)).walk(root: root)
        #expect(f.stopped == "time")
    }

    @Test func cancellingStopsTheWalkAndKeepsWhatWasFound() async throws {
        let root = try fixtureRoot()
        for i in 0..<3000 { try write(root, "d\(i / 100)/f\(i).txt", "x") }
        try write(root, "a/README.md", "x")
        let task = Task.detached { () -> DocWalker.Found in
            while !Task.isCancelled { await Task.yield() }
            return DocWalker().walk(root: root)
        }
        task.cancel()
        let f = await task.value
        #expect(f.stopped == "cancelled")
        #expect(f.checked < 3100)
    }

    @Test func progressIsToldAsItGoes() throws {
        let root = try fixtureRoot()
        for i in 0..<2500 { try write(root, "d\(i / 100)/f\(i).txt", "x") }
        let seen = Seen()
        let f = DocWalker().walk(root: root) { seen.add($0) }
        #expect(seen.values.count >= 2 && seen.values.last == f.checked)
    }
}

final class Seen: @unchecked Sendable {
    private let lock = NSLock()
    private var _v: [Int] = []
    func add(_ n: Int) { lock.withLock { _v.append(n) } }
    var values: [Int] { lock.withLock { _v } }
}
