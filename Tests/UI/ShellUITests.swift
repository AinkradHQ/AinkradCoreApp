import AppKit
import XCTest

/// Keyboard paths of the shell. XCUITest sends events only to the app under test.
@MainActor
final class ShellUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        // Debug hook: after 3 s the app tries to leave full screen by itself, the way a stray toggle would. Only the test that
        // is about it asks: the toggle disables the window for a moment, and a key pressed then is lost.
        if name.contains("testFullScreenStaysOn") { app.launchEnvironment["CORE_EXIT_FS_ATTEMPT"] = "1" }
        app.launchEnvironment["CORE_DEMO"] = "1"
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["Show workspace"].waitForExistence(timeout: 10))
    }

    override func tearDown() async throws { app.terminate() }

    private func element(_ label: String) -> XCUIElement { app.descendants(matching: .any)[label].firstMatch }
    private var launcher: XCUIElement { app.textFields["Launcher"] }

    private func openLauncher() {
        app.typeKey("k", modifierFlags: .command)
        if !launcher.waitForExistence(timeout: 4) {  // the first key after launch can land before the window is key
            app.typeKey("k", modifierFlags: .command)
        }
        XCTAssertTrue(launcher.waitForExistence(timeout: 5), "⌘K opens the launcher")
    }

    func testLauncherOpensAndEscapeCloses() {
        openLauncher()
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(launcher.waitForNonExistence(timeout: 5), "Esc closes the launcher")
        openLauncher()
        app.typeKey("k", modifierFlags: .command)
        XCTAssertTrue(launcher.waitForNonExistence(timeout: 5), "⌘K again closes it")
    }

    func testQueryThenReturnRunsTheEntry() {
        openLauncher()
        launcher.typeText("trm")
        launcher.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(element("Terminals, Rune").waitForExistence(timeout: 5), "trm + Return opens Terminals")
        XCTAssertTrue(launcher.waitForNonExistence(timeout: 5))
    }

    func testCommandNumberPicksTheRow() {
        openLauncher()
        app.typeKey("2", modifierFlags: .command)  // recents: Core, Agents, Terminals
        XCTAssertTrue(element("Agents, Home Core").waitForExistence(timeout: 5), "⌘2 runs the second row")
    }

    func testHomeAndWorkspaceShortcuts() {
        openLauncher()
        launcher.typeText("agents")
        launcher.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.buttons["Show Home"].waitForExistence(timeout: 5), "a pane opens the workspace")
        app.typeKey("0", modifierFlags: .command)
        XCTAssertTrue(app.buttons["Show workspace"].waitForExistence(timeout: 5), "⌘0 shows Home")
        app.typeKey("0", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.buttons["Show Home"].waitForExistence(timeout: 5), "⇧⌘0 shows the workspace")
    }

    func testShortcutSheetAndSettings() {
        app.typeKey("/", modifierFlags: .command)
        XCTAssertTrue(app.textFields["Filter shortcuts"].waitForExistence(timeout: 5), "⌘/ opens the shortcut sheet")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(app.textFields["Filter shortcuts"].waitForNonExistence(timeout: 5))
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(app.buttons["Appearance"].waitForExistence(timeout: 5), "⌘, opens Settings")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(app.buttons["Appearance"].waitForNonExistence(timeout: 5))
    }

    func testFullScreenStaysOn() throws {
        let window = app.windows.firstMatch
        let screen = try XCTUnwrap(NSScreen.main).frame
        sleep(7)  // the debug hook toggled full screen at 3 s; it must have come back by now
        XCTAssertEqual(window.frame.width, screen.width, accuracy: 1, "full screen after a toggle attempt")
        app.typeKey("f", modifierFlags: [.control, .command])  // there is no menu item for it any more
        sleep(3)
        XCTAssertEqual(window.frame.width, screen.width, accuracy: 1, "⌃⌘F does nothing")
        let zoom = window.buttons[XCUIIdentifierFullScreenWindow]
        if zoom.exists { XCTAssertFalse(zoom.isEnabled, "the green button is disabled") }
    }

    func testMenuItemsFollowTheState() {
        let close = app.menuBars.menuBarItems["File"].menuItems["Close Pane"]
        XCTAssertTrue(close.exists)
        XCTAssertFalse(close.isEnabled, "no pane open: Close Pane is disabled")
        openLauncher()
        launcher.typeText("agents")
        launcher.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.buttons["Show Home"].waitForExistence(timeout: 5))
        let enabled = NSPredicate(format: "isEnabled == true")
        let wait = XCTNSPredicateExpectation(predicate: enabled, object: close)
        XCTAssertEqual(XCTWaiter().wait(for: [wait], timeout: 5), .completed, "a pane is open: Close Pane is enabled")
    }
}
