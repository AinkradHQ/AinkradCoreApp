import CoreKit
import Foundation
import Testing

@testable import Shell

private struct Refused: LocalizedError { var errorDescription: String? { "No." } }

private actor FakeCore: CorePageSource {
    var minor95 = true
    var stored = CorePagePrefs(name: "Home", crashReports: false, autoUpdate: true, updateHour: 3)
    var refuse = false
    func supported() async -> Bool { minor95 }
    func prefs() async throws -> CorePagePrefs { stored }
    func set(name: String?, crashReports: Bool?, autoUpdate: Bool?, updateHour: Int?) async throws -> CorePagePrefs {
        if refuse { throw Refused() }
        if let name { stored.name = name }
        if let crashReports { stored.crashReports = crashReports }
        if let autoUpdate { stored.autoUpdate = autoUpdate }
        if let updateHour { stored.updateHour = updateHour }
        return stored
    }
    func storage() async throws -> CorePageStorage { CorePageStorage(backups: 5, backupsCount: 2) }
    func checkUpdate() async throws -> (at: Date, feed: Bool) { (Date(timeIntervalSince1970: 100), false) }
    var backupInfo = CoreBackups(schedule: "daily")
    var started = 0
    func backups() async throws -> CoreBackups? { backupInfo }
    func backupNow() async throws {
        if refuse { throw Refused() }
        started += 1
        backupInfo.running = true
    }
    func setMinor95(_ on: Bool) { minor95 = on }
    func setRefuse(_ on: Bool) { refuse = on }
}

@MainActor
struct CorePageModelTests {
    @Test func anOlderCoreIsNotSupportedAndNothingIsWritten() async {
        let core = FakeCore()
        await core.setMinor95(false)
        let m = CorePageModel()
        m.source = core
        await m.load()
        await m.save(name: "New")
        #expect(!m.supported && m.prefs.name == nil)
        #expect(await core.stored.name == "Home")
    }

    @Test func aSaveKeepsWhatTheCoreAnswers() async {
        let m = CorePageModel()
        m.source = FakeCore()
        await m.load()
        #expect(m.supported && m.prefs.name == "Home")
        await m.save(crashReports: true, updateHour: 6)
        #expect(m.prefs.crashReports && m.prefs.updateHour == 6 && m.prefs.name == "Home")
    }

    @Test func aRefusedSaveShowsTheReasonAndTheCoresValue() async {
        let core = FakeCore()
        let m = CorePageModel()
        m.source = core
        await m.load()
        await core.setRefuse(true)
        await m.save(name: "Nope")
        #expect(m.failure == "No." && m.prefs.name == "Home")
    }

    @Test func checkNowRecordsTheTimeAndSaysThereIsNoFeed() async {
        let m = CorePageModel()
        m.source = FakeCore()
        await m.load()
        await m.checkNow()
        #expect(m.prefs.updateCheckedAt == Date(timeIntervalSince1970: 100))
        #expect(m.checkNote?.contains("No release feed") == true)
    }

    @Test func droppingTheSourceClearsEverything() async {
        let m = CorePageModel()
        m.source = FakeCore()
        await m.load()
        await m.loadStorage()
        #expect(m.storage?.backupsCount == 2)
        m.source = nil
        #expect(!m.supported && m.storage == nil && m.prefs.name == nil)
    }

    @Test func backUpNowStartsOnceAndReadsTheScheduleAgain() async {
        let core = FakeCore()
        let m = CorePageModel()
        m.source = core
        await m.load()
        await m.loadBackups()
        #expect(m.backups?.scheduleWords == "Every day" && m.backups?.running == false)
        await m.backupNow()
        #expect(await core.started == 1)
        #expect(m.backups?.running == true)
        #expect(m.backupNote == "Backup started. It finishes by itself.")
    }

    @Test func anOlderCoreNeitherReadsNorStartsBackups() async {
        let core = FakeCore()
        await core.setMinor95(false)
        let m = CorePageModel()
        m.source = core
        await m.load()
        await m.loadBackups()
        await m.backupNow()
        #expect(m.backups == nil)
        #expect(await core.started == 0)
    }
}
