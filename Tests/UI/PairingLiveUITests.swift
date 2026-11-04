import XCTest

/// Pairs the app with a real local Core, end to end. Only with `CORE_IT=1`: `scripts/app-it.sh uitest` starts a throwaway Core,
/// makes the code, and plays the approver (it reads the check code the app wrote to CORE_IT_SAS_FILE and approves with it).
/// Events go only to the app under test.
@MainActor
final class PairingLiveUITests: XCTestCase {
    private let env = ProcessInfo.processInfo.environment

    func testPairsWithALocalCoreAndShowsThisMacInDevices() throws {
        try XCTSkipUnless(env["CORE_IT"] == "1", "needs a local Core: run scripts/app-it.sh uitest")
        let sasFile = try XCTUnwrap(env["CORE_IT_SAS_FILE"])

        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["CORE_KEYSTORE"] = "memory"  // no Keychain: this run leaves nothing behind
        app.launchEnvironment["CORE_IT_SAS_FILE"] = sasFile
        app.launch()
        defer { app.terminate() }

        try LivePairing.pair(app, env: env)

        app.typeKey(",", modifierFlags: .command)
        let devices = app.buttons["Devices"]
        XCTAssertTrue(devices.waitForExistence(timeout: 10), "Settings opens")
        devices.click()
        let me = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'This Mac'")).firstMatch
        XCTAssertTrue(me.waitForExistence(timeout: 20), "Devices lists this Mac from the Core")
        XCTAssertTrue(app.buttons["Add device…"].exists)
        me.click()
        XCTAssertTrue(app.buttons["Rename…"].waitForExistence(timeout: 10), "the device page has its actions")
        XCTAssertTrue(app.buttons["Revoke…"].exists)
        app.buttons["Back to Devices"].click()
        XCTAssertTrue(app.buttons["Add device…"].waitForExistence(timeout: 10), "Back returns to the list")
    }
}
