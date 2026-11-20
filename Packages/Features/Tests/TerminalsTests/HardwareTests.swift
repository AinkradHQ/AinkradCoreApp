import AinkradClient
import Foundation
import Shell
import Testing

@testable import Terminals

@MainActor
@Suite(.serialized) struct HardwareTests {
    static let json = """
        [{"id":"d_mac","name":"Studio","kind":"mac","online":true,"degraded":false,"paused_until":null,
          "gate":"on_battery","os":"macos","arch":"aarch64","cores":10,"cpu_pct":42,"mem_total_mb":16384,
          "mem_free_mb":4096,"battery":{"on_battery":true,"percent":61},"toolchains":{"rust":"1.88.0","swift":""},
          "sessions":2,"jobs":[{"id":"j_1","project":3,"label":"cargo build","started_at":"2026-11-20T10:00:00.250Z"}],
          "job_slots":2}]
        """

    func hw(
        _ id: String = "d_mac", kind: String = "mac", gate: String = "open", paused: Date? = nil, cpu: Int = 10
    ) -> HardwareItem {
        HardwareItem(
            id: id, name: id, kind: kind, online: true, degraded: false, pausedUntil: paused, gate: gate, os: nil,
            arch: nil, cores: 8, cpuPct: cpu, memTotalMb: 16384, memFreeMb: 8192, battery: nil, toolchains: [:],
            sessions: 0, jobs: [], jobSlots: 2)
    }

    @Test func theCoresHardwareJsonDecodesAndSaysItInWords() throws {
        let wire = try HardwareWire.decoder.decode([Components.Schemas.Hardware].self, from: Data(Self.json.utf8))
        let list = wire.map(LiveTerminalService.hardware)
        let f = HardwareFacts(list[0])
        #expect(list[0].jobs.first?.label == "cargo build")
        #expect(f.gateWords == "On battery: takes no jobs")
        #expect(f.memWords == "12 of 16 GB RAM in use")
        #expect(f.cpuWords == "42% of 10 cores")
        #expect(f.toolchains == ["rust 1.88.0", "swift"])
        #expect(f.battery == "On battery, 61%")
        #expect(f.doing == "2 AI sessions · 1 job")
    }

    @Test func aPauseWinsOverTheMachinesOwnGate() {
        let until = Date.now.addingTimeInterval(3600)
        #expect(HardwareFacts(hw(paused: until)).gateWords.hasPrefix("Paused until "))
        #expect(HardwareFacts(hw(paused: PauseSpan.forever)).gateWords == "Paused until you resume")
        #expect(HardwareFacts(hw(paused: .distantPast)).gateWords == "Takes new work")
    }

    @Test func pauseSpansEndWhereTheMenuSays() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(PauseSpan.hour.until(now: now) == now.addingTimeInterval(3600))
        #expect(PauseSpan.resume.until(now: now) == nil)
        let t = PauseSpan.tomorrow.until(now: now)!
        #expect(t > now && t < now.addingTimeInterval(2 * 86_400))
        #expect(PauseSpan.isForever(PauseSpan.indefinite.until(now: now)!))
    }

    @Test func ranOnSaysNothingForTheCoreAndNamesAnyOtherMachine() {
        #expect(JobPlace(deviceName: "Core", reason: .core).words == nil)
        #expect(JobPlace(deviceName: "Studio", reason: .thisMac).words == "Ran on Studio")
        #expect(JobPlace(deviceName: "Box", reason: .overflow, state: "running").words == "Overflow · running on Box")
        #expect(JobPlace(deviceName: "Box", reason: .runner, state: "running").words == "Running on Box")
        #expect(JobPlace(deviceName: "Box", reason: .runner, state: "lost").words == "Lost on Box")
        let none = JobPlace(deviceName: "Core", reason: .coreNoFit, missing: "xcode")
        #expect(none.words == "Ran on Core")
        #expect(none.why.contains("xcode"))
    }

    @Test func theDeckFillsOnlyWhenTheCoreAnswersHardware() async {
        let svc = FakeService()
        let m = TerminalsModel(host: FakeHost(), service: svc)
        await m.refreshHardware()
        #expect(!m.hardwareOn && m.shell.hardwareDeck.bar == nil)

        svc.hardwareList = [hw("d_core", kind: "core"), hw("d_mac")]
        svc.poolItem = HardwarePoolItem(loadPct: 37, jobs: 1, sessions: 2, paused: false)
        svc.jobList = [
            JobItem(
                id: "j_1", project: 3, session: "as_1", terminal: "t_1", label: "cargo build", deviceName: "Studio",
                placeReason: "this_mac", missing: nil, state: "ended",
                startedAt: Date(timeIntervalSince1970: 1_800_000_010))
        ]
        await m.refreshHardware()
        let deck = m.shell.hardwareDeck
        #expect(deck.bar?.loadPct == 37)
        #expect(deck.bar?.macs.map(\.id) == ["d_mac"], "the Core is never paused by itself")
        #expect(deck.jobByTerminal["t_1"]?.words == "Ran on Studio")
        #expect(deck.jobByProject[3]?.deviceName == "Studio")
        #expect(deck.place(session: "as_9", runner: "d_mac")?.words == "Ran on d_mac")
        #expect(deck.place(session: "as_9", runner: "d_core") == nil)
        #expect(m.cpuSamples["d_mac"] == [10])
    }

    @Test func remoteHardwareOpensNoTerminalsOnceTheCoreHasHardware() async {
        let svc = FakeService()
        var remote = runner("r2", name: "box")
        var core = runner("r_core", name: "core")
        core.builtIn = true
        remote.builtIn = false
        let host = FakeHost()
        host.macID = "r_mac"
        let m = TerminalsModel(host: host, service: svc)
        #expect(!m.hidesTerminals(remote))
        svc.hardwareList = [hw("r2", kind: "runner")]
        await m.refreshHardware()
        #expect(m.hidesTerminals(remote) && !m.hidesTerminals(core) && !m.hidesTerminals(runner("r_mac")))
    }

    @Test func pausingGoesThroughTouchIDAndLiftsWithNil() async {
        let svc = FakeService()
        let host = FakeHost()
        let m = TerminalsModel(host: host, service: svc)
        await m.pause("d_mac", .hour)
        await m.pause(nil, .resume)
        #expect(svc.pauses.map(\.id) == ["d_mac", nil])
        #expect(svc.pauses[0].until != nil && svc.pauses[1].until == nil)
        #expect(host.reasons.count == 2 && host.reasons[1] == "Resume all hardware")
    }

    @Test func aDeclinedTouchIDPausesNothing() async {
        let svc = FakeService()
        let host = FakeHost()
        host.declines = true
        let m = TerminalsModel(host: host, service: svc)
        await m.pause("d_mac", .indefinite)
        #expect(svc.pauses.isEmpty)
    }

    @Test func aSessionsPlaceReasonSaysOverflowAndAJobMatchesTheStepItStartedIn() async {
        let svc = FakeService()
        let m = TerminalsModel(host: FakeHost(), service: svc)
        svc.hardwareList = [hw("d_core", kind: "core"), hw("d_box", kind: "runner")]
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        svc.jobList = [
            JobItem(
                id: "j_1", project: nil, session: "as_1", terminal: nil, label: "cargo build", deviceName: "box",
                placeReason: "runner", missing: nil, state: "ended", startedAt: t0.addingTimeInterval(5))
        ]
        await m.refreshHardware()
        let deck = m.shell.hardwareDeck
        #expect(
            deck.place(session: "as_2", runner: "d_box", placeReason: "overflow")?.words == "Overflow · ran on d_box")
        #expect(deck.place(session: "as_2", runner: "d_core", placeReason: "overflow") == nil)
        // A step that ran t0 to t0 + 20 s owns the job that started at t0 + 5 s; one that ended before does not.
        #expect(deck.place(session: "as_1", from: t0, until: t0.addingTimeInterval(20))?.words == "Ran on box")
        #expect(deck.place(session: "as_1", from: t0.addingTimeInterval(-30), until: t0.addingTimeInterval(-10)) == nil)
        #expect(deck.place(session: "as_9", from: t0, until: nil) == nil, "another session's job is never matched")
        #expect(deck.place(session: "as_1", from: t0, until: nil)?.deviceName == "box", "a running step has no end yet")
    }
}
