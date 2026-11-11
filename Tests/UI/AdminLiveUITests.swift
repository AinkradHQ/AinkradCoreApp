import XCTest

/// The admin screens end to end, against a real local Core. Only with `CORE_IT=1`: `scripts/app-it.sh admin` starts a throwaway
/// Core and approves the app's pairing. Toggles a feature switch, stores a dummy secret named `e5-07-test`, reads its metadata
/// and finds the audit rows for both. The value is typed once and must be found nowhere on screen afterwards. The app keeps its
/// keys in memory and elevates with a software step-up key, so no Touch ID prompt appears. Events go only to the app under test.
@MainActor
final class AdminLiveUITests: XCTestCase {
    private let env = ProcessInfo.processInfo.environment
    private var app: XCUIApplication!
    private static let secretName = "e5-07-test"
    private static let dummyValue = "dummy-throwaway-9f3a1c27"

    private func element(_ label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ OR identifier == %@", label, label))
            .firstMatch
    }
    private func element(containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", text, text)
        ).firstMatch
    }

    private func openSection(_ query: String, expect title: String) {
        app.typeKey(.escape, modifierFlags: [])  // closes Settings when it is open
        app.typeKey("k", modifierFlags: .command)
        let launcher = app.textFields["Launcher"]
        if !launcher.waitForExistence(timeout: 4) { app.typeKey("k", modifierFlags: .command) }
        XCTAssertTrue(launcher.waitForExistence(timeout: 10), "⌘K opens the launcher")
        launcher.typeText(query)
        launcher.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 15), "Settings shows \(title)")
    }

    /// What the window showed when a step did not happen, for the person reading the failure.
    private func shot(_ name: String) {
        guard let dir = env["CORE_IT_SHOTS"] else { return }
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/admin-live-\(name).png"))
    }

    private func wait(_ predicate: @escaping () -> Bool, timeout: TimeInterval = 30, _ message: String) {
        let done = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in predicate() }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [done], timeout: timeout), .completed, message)
    }

    func testSwitchSecretAndAudit() throws {
        try XCTSkipUnless(env["CORE_IT"] == "1", "needs a local Core: run scripts/app-it.sh admin")
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["CORE_KEYSTORE"] = "memory"
        app.launchEnvironment["CORE_IT_SAS_FILE"] = try XCTUnwrap(env["CORE_IT_SAS_FILE"])
        app.launch()
        defer { app.terminate() }
        try LivePairing.pair(app, env: env)

        // Feature switches: the passkey switch goes on, then the broker moves to Throwaway (secrets need it).
        openSection("feature switches", expect: "Feature switches")
        let passkey = element("switch-auth.passkey_admin")
        XCTAssertTrue(passkey.waitForExistence(timeout: 20), "the passkey switch is listed")
        XCTAssertEqual(passkey.value as? String, "Off", "off by default")
        passkey.click()
        wait({ (passkey.value as? String) == "On" }, "the switch is on after Touch ID (software key)")
        XCTAssertTrue(app.buttons["Test keys"].waitForExistence(timeout: 10), "the broker modes are listed")
        app.buttons["Test keys"].click()
        wait({ self.app.buttons["Test keys"].isSelected }, "the broker is on Test keys")
        XCTAssertTrue(
            app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Test keys, step 2 of 3'"))
                .firstMatch.waitForExistence(timeout: 10), "the step track follows")

        // Secrets: store a dummy value and see only its metadata.
        openSection("secrets", expect: "Secrets")
        let new = app.buttons["New secret…"].firstMatch
        XCTAssertTrue(new.waitForExistence(timeout: 20), "an empty Core offers New secret")
        new.click()
        // The wizard (N24): Text is the type, then the value, then the name.
        let nextButton = app.buttons["Next"]
        XCTAssertTrue(nextButton.waitForExistence(timeout: 10), "the New secret wizard opens")
        nextButton.click()
        let value = app.secureTextFields["Value"]
        XCTAssertTrue(value.waitForExistence(timeout: 10), "the value step opens")
        value.click()
        value.typeText(Self.dummyValue)
        nextButton.click()
        let name = app.textFields["Name"]
        XCTAssertTrue(name.waitForExistence(timeout: 10), "the details step opens")
        name.click()
        name.typeText(Self.secretName)
        app.buttons["Seal secret"].click()
        let card = element("secret-\(Self.secretName)")
        XCTAssertTrue(card.waitForExistence(timeout: 30), "the secret is listed by name")
        let note = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS 'Mode 1' OR value CONTAINS 'Mode 1'")
        ).firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 20), "the note follows the Core's mode")

        XCTAssertTrue(
            element("Value, \(Self.dummyValue.utf8.count) bytes, hidden").exists, "its size, never its content")
        XCTAssertTrue(element(containing: "Version").exists && element(containing: "v1").exists, "version 1")
        let leaks = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "label CONTAINS %@ OR value CONTAINS %@ OR title CONTAINS %@", Self.dummyValue, Self.dummyValue,
                Self.dummyValue))
        XCTAssertEqual(leaks.count, 0, "the value is on no screen")

        // Audit: both changes are there, and the kind filter narrows the list.
        openSection("audit", expect: "Audit")
        XCTAssertTrue(element(containing: "secret.created").waitForExistence(timeout: 30), "the store is audited")
        XCTAssertTrue(element(containing: "setting.set").exists, "the switch changes are audited")
        let kind = app.textFields["Kind"]
        kind.click()
        kind.typeText("secret.")
        wait({ !self.element(containing: "setting.set").exists }, "the kind filter hides the setting rows")
        XCTAssertTrue(element(containing: "secret.created").exists)
    }
}
