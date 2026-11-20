import Foundation
import Testing

@testable import CoreKit

@Suite struct CrashReportTests {
    @Test func aReportCarriesOnlyWhatTheWorkerAccepts() throws {
        let r = CrashReport(
            version: "0.10.1", os: "macOS 27.2", arch: "arm64", kind: "NSRangeException\n/Users/sam/secret",
            frames: ["Ainkrad+0x1a2", "x\ny"])
        #expect(r.kind == "NSRangeException", "only the first word of a kind survives, never a path")
        #expect(r.frames == ["Ainkrad+0x1a2"], "a frame that is not Module+0xOffset is dropped")
        let leak = CrashReport(
            version: "1", os: "macOS", arch: "arm64", kind: "crash",
            frames: ["/Users/sam/Ainkrad+0x1", "sam's Mac+0x1", "Ok+0xZZ", "Ok+0x1f"])
        #expect(leak.frames == ["Ok+0x1f"], "paths, spaces and non-hex offsets never pass")
        let keys = Set(
            try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(r)) as? [String: Any]).keys)
        #expect(keys == ["app", "version", "os", "arch", "kind", "frames"], "no message, no id, no path")
    }

    @Test func framesComeFromTheCrashingThreadOnly() {
        let json = """
            {"callStackPerThread":true,"callStacks":[
              {"threadAttributed":false,"callStackRootFrames":[{"binaryName":"Other","offsetIntoBinaryTextSegment":1}]},
              {"threadAttributed":true,"callStackRootFrames":[{"binaryName":"Ainkrad","offsetIntoBinaryTextSegment":255,
                "subFrames":[{"binaryName":"libsystem_c.dylib","offsetIntoBinaryTextSegment":16}]}]}]}
            """
        #expect(CrashReport.frames(fromCallStackTree: Data(json.utf8)) == ["Ainkrad+0xff", "libsystem_c.dylib+0x10"])
        #expect(CrashReport.frames(fromCallStackTree: Data("junk".utf8)).isEmpty)
    }

    @Test func spoolSendsWhenAllowedAndDeletesUnsentWhenNot() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("crash-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let r = CrashReport(version: "1", os: "macOS", arch: "arm64", kind: "crash", frames: [])
        CrashSpool.write(r, in: dir)
        await CrashSpool.flush(enabled: true, in: dir, send: { _ in 0 })  // offline: kept
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).count == 1)
        await CrashSpool.flush(enabled: true, in: dir, send: { _ in 204 })
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
        CrashSpool.write(r, in: dir)
        await CrashSpool.flush(
            enabled: false, in: dir,
            send: { _ in
                Issue.record("sent while off")
                return 204
            })
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty, "off discards what was waiting")
    }
}
