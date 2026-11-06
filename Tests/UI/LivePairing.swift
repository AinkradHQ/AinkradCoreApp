import XCTest

/// Pairs the launched app with the local throwaway Core the way a person does: typed code, check code compared, approver
/// approves (`scripts/app-it.sh` plays it from the file the app writes). Leaves the desktop open.
@MainActor
enum LivePairing {
    static func pair(_ app: XCUIApplication, env: [String: String]) throws {
        let url = try XCTUnwrap(env["CORE_IT_URL"])
        let code = try XCTUnwrap(env["CORE_IT_CODE"])  // ABCDEFGHJK, no dash
        let sasFile = try XCTUnwrap(env["CORE_IT_SAS_FILE"])
        // Setup: who you are (skipped), where the Core is, the code.
        let notNow = app.buttons["Not now"]
        XCTAssertTrue(notNow.waitForExistence(timeout: 20), "first run starts with the name step")
        XCTAssertFalse(app.buttons["Show workspace"].exists, "no desktop before pairing")
        notNow.click()
        let address = app.textFields["Core address"]
        XCTAssertTrue(address.waitForExistence(timeout: 20), "first run shows the connect form")
        address.click()
        address.typeText(url)
        app.buttons["Continue"].click()
        let pair = app.buttons["Pair this Mac"]
        let field = app.textFields["Pairing code"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "the code step opens")
        XCTAssertFalse(pair.isEnabled, "nothing typed: Pair is off")
        field.click()
        field.typeText(code.lowercased())  // typed in lower case, no dash: it formats itself
        let dashed = "\(code.prefix(5))-\(code.dropFirst(5))"
        let formatted = NSPredicate(format: "value == %@ OR value == %@", dashed, code)
        let wait = XCTNSPredicateExpectation(predicate: formatted, object: field)
        XCTAssertEqual(XCTWaiter().wait(for: [wait], timeout: 5), .completed, "case-insensitive")
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

        let open = app.buttons["Open Ainkrad"]
        XCTAssertTrue(open.waitForExistence(timeout: 90), "the approver approved with the same check code")
        open.click()

        XCTAssertTrue(app.buttons["Show workspace"].waitForExistence(timeout: 30), "the desktop opens")
        // Live, the bar names no Core state: "Connecting" goes away once the link is up.
        let connecting = app.buttons["Home Core, connecting"]
        XCTAssertTrue(
            connecting.waitForNonExistence(timeout: 30) && !app.buttons["Home Core, offline"].exists,
            "the status cluster is live")

    }
}
