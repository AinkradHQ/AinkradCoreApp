import XCTest

/// Runs the app's own screenshot walk (`CORE_PAIR_SNAPSHOT`, Debug only) and waits for it to quit. The app captures its own
/// window and sends no key events; this test only launches it with the window server it needs and forwards the environment.
/// Only with `CORE_SHOTS=1`: `scripts/app-it.sh shots` sets everything up.
@MainActor
final class SnapshotWalkUITests: XCTestCase {
    func testWalk() throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["CORE_SHOTS"] == "1", "needs scripts/app-it.sh shots")
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["CORE_KEYSTORE"] = "memory"
        for key in [
            "CORE_PAIR_SNAPSHOT", "CORE_HOME_SNAPSHOT", "CORE_AGENTS_SNAPSHOT", "CORE_TERM_SNAPSHOT",
            "CORE_TERM_SCENES",
            "CORE_ADMIN_SNAPSHOT", "CORE_ADMIN_SCENES",
            "CORE_ACC_SNAPSHOT", "CORE_ACC_SCENES", "CORE_BRAIN_SNAPSHOT", "CORE_BRAIN_SCENES",
            "CORE_DEMO", "CORE_SNAPSHOT", "CORE_ALLOW_CAPTURE",
            "CORE_GALLERY_SNAPSHOT", "CORE_THEME", "CORE_IT_URL", "CORE_IT_CODE", "CORE_IT_SAS_FILE",
            "CORE_IT_ADD_CODE_FILE",
            "CORE_IT_LOCKS_READY",
        ] {
            if let v = env[key] { app.launchEnvironment[key] = v }
        }
        app.launch()
        let gone = NSPredicate(format: "state == %d", XCUIApplication.State.notRunning.rawValue)
        let done = XCTNSPredicateExpectation(predicate: gone, object: app)
        XCTAssertEqual(XCTWaiter().wait(for: [done], timeout: 420), .completed, "the walk finished and the app quit")
    }
}
