import Foundation
import Testing

@testable import Leyline

struct HostPageTests {
    @Test func remotePathsStayData() {
        #expect(RemotePath.parent("/srv/app") == "/srv")
        #expect(RemotePath.parent("/srv") == "/")
        #expect(RemotePath.join("/", "a") == "/a")
        #expect(RemotePath.join("/srv", "-rf") == "/srv/-rf")
        #expect(RemotePath.crumbs("/srv/app").map(\.name) == ["/", "srv", "app"])
        #expect(RemotePath.safeName("../x") == ".._x")
    }

    @Test func recordingKeepsOutputAndDropsControlBytes() {
        let cast = """
            {"version":2}
            [0.5,"o","\\u001b[32mhi\\u001b[0m\\r\\n"]
            [1.0,"i","secret"]
            [2.0,"o","bye"]
            """
        let r = Recording.parse(Data(cast.utf8))
        #expect(r.frames.count == 2)
        #expect(r.length == 2.0)
        #expect(r.text(at: 1.0) == "hi\n")
        #expect(r.text(at: 2.0) == "hi\nbye")
    }

    @Test func secretLookingFilesAreLocked() {
        func f(_ n: String) -> RemoteFile {
            RemoteFile(path: "/" + n, name: n, kind: .file, size: 1, modified: nil, target: nil)
        }
        #expect(f(".env").mayHoldSecrets && f("id_ed25519").mayHoldSecrets && f("a.pem").mayHoldSecrets)
        #expect(!f("composer.json").mayHoldSecrets)
    }

    @Test func commandsFitTheirScope() {
        let h = HostItem(
            id: "h_1", name: "web-1", address: "192.0.2.1", port: 22, username: "u", keyID: nil, jumpChain: [],
            viaRunner: nil, group: "shop", tags: ["eu"], aiRule: .ask, os: nil, createdAt: nil)
        func c(_ kind: String?, _ value: String?) -> PresetCommand {
            PresetCommand(
                id: "c", name: "n", description: "", steps: ["w"], scopeKind: kind, scopeValue: value, readOnly: false,
                confirm: false)
        }
        #expect(
            c(nil, nil).fits(h) && c("host", "web-1").fits(h) && c("group", "shop").fits(h) && c("tag", "eu").fits(h))
        #expect(!c("host", "db-1").fits(h) && !c("group", "ops").fits(h) && !c("tag", "us").fits(h))
    }

    @Test func healthDecodesWithGaps() throws {
        let json =
            #"{"state":"up","checked_at":"2026-11-18T10:00:00Z","load1":1.0,"cpus":2,"mem_pct":61.0,"history":[{"load1":0.5,"cpus":2}]}"#
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        let h = try d.decode(HealthWire.self, from: Data(json.utf8)).item
        #expect(h.state == .up && h.cpuPct == 50 && h.diskPct == nil && h.cpuSeries == [25])
    }
}
