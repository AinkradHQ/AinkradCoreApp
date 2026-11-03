import XCTest

/// Pairs the app with a real local Core, end to end. Only with `CORE_IT=1`: `scripts/app-it.sh uitest` starts a throwaway Core,
/// makes the code, and plays the approver (it reads the check code the app wrote to CORE_IT_SAS_FILE and approves with it).
/// Events go only to the app under test.
@MainActor
final class PairingLiveUITests: XCTestCase {
    private let env = ProcessInfo.processInfo.environment

    func testPairsWithALocalCoreAndShowsThisMacInDevices() throws {
        try XCTSkipUnless(env["CORE_IT"] == "1", "needs a local Core: run scripts/app-it.sh uitest")
        let url = try XCTUnwrap(env["CORE_IT_URL"])
        let code = try XCTUnwrap(env["CORE_IT_CODE"])  // ABCDEFGHJK, no dash
        let sasFile = try XCTUnwrap(env["CORE_IT_SAS_FILE"])

        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["CORE_KEYSTORE"] = "memory"  // no Keychain: this run leaves nothing behind
        app.launchEnvironment["CORE_IT_SAS_FILE"] = sasFile
        app.launch()
        defer { app.terminate() }

        let address = app.textFields["Core address"]
        XCTAssertTrue(address.waitForExistence(timeout: 20), "first run shows the connect form")
        XCTAssertFalse(app.buttons["Show workspace"].exists, "no desktop before pairing")
        let pair = app.buttons["Pair this Mac"]
        XCTAssertFalse(pair.isEnabled, "nothing typed: Pair is off")

        address.click()
        address.typeText(url)
        let field = app.textFields["Pairing code or QR text"]
        field.click()
        field.typeText(code.lowercased())  // typed in lower case, no dash: it formats itself
        let dashed = "\(code.prefix(5))-\(code.dropFirst(5))"
        let formatted = NSPredicate(format: "value == %@", dashed)
        let wait = XCTNSPredicateExpectation(predicate: formatted, object: field)
        XCTAssertEqual(XCTWaiter().wait(for: [wait], timeout: 5), .completed, "case-insensitive, auto-dash")
        XCTAssertTrue(pair.isEnabled)
        pair.click()

        let sas = app.descendants(matching: .any)["sas"].firstMatch
        XCTAssertTrue(sas.waitForExistence(timeout: 30), "the claim shows the check code")
        let shown = (sas.label).replacingOccurrences(of: "Check code ", with: "").replacingOccurrences(
            of: " ", with: "")
        XCTAssertEqual(shown.count, 16, "16 characters in four groups")
        if let written = try? String(contentsOfFile: sasFile, encoding: .utf8) {
            XCTAssertEqual(
                written.replacingOccurrences(of: "-", with: ""), shown,
                "the file the approver reads is what is on screen")
        }
        app.buttons["It matches"].click()

        let open = app.buttons["Open Ainkrad Core"]
        XCTAssertTrue(open.waitForExistence(timeout: 90), "the approver approved with the same check code")
        open.click()

        XCTAssertTrue(app.buttons["Show workspace"].waitForExistence(timeout: 30), "the desktop opens")
        XCTAssertTrue(app.buttons["Home Core, connected"].waitForExistence(timeout: 30), "the status cluster is live")

        app.typeKey(",", modifierFlags: .command)
        let devices = app.buttons["Devices"]
        XCTAssertTrue(devices.waitForExistence(timeout: 10), "Settings opens")
        devices.click()
        let me = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'This Mac'")).firstMatch
        XCTAssertTrue(me.waitForExistence(timeout: 20), "Devices lists this Mac from the Core")
        XCTAssertTrue(app.descendants(matching: .any)["Rename mac-app"].exists, "the row has its actions")
        XCTAssertTrue(app.buttons["Add device"].exists)
    }
}
