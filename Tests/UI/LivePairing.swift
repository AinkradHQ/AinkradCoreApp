import XCTest

/// Pairs the app under test with the throwaway Core by typing the code, comparing the check code and waiting for the approver
/// (`scripts/app-it.sh` plays it). The same steps as `PairingLiveUITests`, for tests that go on from a paired desktop.
@MainActor
enum LivePairing {
    static func pair(_ app: XCUIApplication, url: String, code: String, sasFile: String?) throws {
        let address = app.textFields["Core address"]
        XCTAssertTrue(address.waitForExistence(timeout: 20), "first run shows the connect form")
        address.click()
        address.typeText(url)
        let field = app.textFields["Pairing code"]
        field.click()
        field.typeText(code.lowercased())
        let pair = app.buttons["Pair this Mac"]
        XCTAssertTrue(pair.waitForExistence(timeout: 5) && pair.isEnabled)
        pair.click()
        XCTAssertTrue(
            app.descendants(matching: .any)["sas"].firstMatch.waitForExistence(timeout: 30),
            "the claim shows the check code")
        app.buttons["It matches"].click()
        let open = app.buttons["Open Ainkrad Core"]
        XCTAssertTrue(open.waitForExistence(timeout: 90), "the approver approved with the same check code")
        open.click()
        XCTAssertTrue(app.buttons["Show workspace"].waitForExistence(timeout: 30), "the desktop opens")
        XCTAssertTrue(app.buttons["Home Core, connected"].waitForExistence(timeout: 30), "the status cluster is live")
    }
}
