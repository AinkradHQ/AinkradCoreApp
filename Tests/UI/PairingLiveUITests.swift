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
        XCTAssertTrue(app.buttons["Rename"].waitForExistence(timeout: 10), "the device page has its actions")
        XCTAssertTrue(app.buttons["Revoke device"].exists)
        app.buttons["Back to Devices"].click()
        XCTAssertTrue(app.buttons["Add device…"].waitForExistence(timeout: 10), "Back returns to the list")

        // Add device with the admin scope (this Mac holds it): a code, not "This device is not allowed to do that".
        app.buttons["Add device…"].click()
        let name = app.textFields["Device name"]
        XCTAssertTrue(name.waitForExistence(timeout: 10), "Add device opens")
        name.click()
        name.typeText("second-mac")
        let admin = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'admin'")).firstMatch
        XCTAssertTrue(admin.waitForExistence(timeout: 5), "the admin scope is offered")
        admin.click()
        app.buttons["Create pairing"].click()
        let code = app.descendants(matching: .any)["pairing-code"].firstMatch
        XCTAssertTrue(code.waitForExistence(timeout: 30), "the typed code is shown, not an error")
        XCTAssertFalse(app.staticTexts["This device is not allowed to do that."].exists, "no refusal")
        // The typed code is on the card as text (spoken character by character), not only in the QR.
        XCTAssertTrue(code.label.hasPrefix("Pairing code "), "the code is readable: \(code.label)")
        XCTAssertGreaterThanOrEqual(code.label.split(separator: " ").count, 12, "spoken one character at a time")
        app.buttons["Cancel pairing"].click()
        let close = app.buttons["Close"]
        XCTAssertTrue(close.waitForExistence(timeout: 20), "the pairing ended")
        close.click()
        XCTAssertTrue(name.waitForNonExistence(timeout: 10))

        // Forget this Core: in Settings, behind a confirmation; it returns to the connect screen.
        app.typeKey(",", modifierFlags: .command)
        let forget = app.buttons["Forget this Core"]
        XCTAssertTrue(forget.waitForExistence(timeout: 10), "Settings → Core has Forget this Core")
        forget.click()
        let open = app.buttons["Forget this Core…"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.click()
        let confirm = app.buttons["Forget Core"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "the confirmation asks first")
        confirm.click()
        let setup = NSPredicate { _, _ in
            app.textFields["Pairing code"].exists || app.textFields["Core address"].exists
        }
        XCTAssertEqual(
            XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: setup, object: nil)], timeout: 20), .completed,
            "back on the setup screens, no desktop")
        XCTAssertFalse(app.buttons["Show workspace"].exists)
    }
}
