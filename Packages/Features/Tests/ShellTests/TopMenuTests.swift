import Testing

@testable import Shell

@MainActor
struct TopMenuTests {
    @Test func oneDropdownAtATime() {
        let shell = ShellModel()
        shell.toggleMenu(.runners)
        #expect(shell.topMenu == .runners)
        shell.toggleMenu(.brain)
        #expect(shell.topMenu == .brain)
        shell.toggleMenu(.brain)
        #expect(shell.topMenu == nil)
    }

    @Test func theBellAndLauncherCloseADropdown() {
        let shell = ShellModel()
        shell.toggleMenu(.core)
        shell.toggleBell()
        #expect(shell.topMenu == nil && shell.bellOpen)
        shell.toggleMenu(.runners)
        #expect(!shell.bellOpen && shell.topMenu == .runners)
        shell.toggleLauncher()
        #expect(shell.topMenu == nil)
    }

    @Test func connectionPanelIsTheCoreDropdownAndEscapeClosesIt() {
        let shell = ShellModel()
        shell.connectionPanelOpen = true
        #expect(shell.topMenu == .core && shell.coverOpen)
        shell.connectionPanelOpen = false
        #expect(shell.topMenu == nil)
        shell.toggleMenu(.brain)
        shell.connectionPanelOpen = false  // closing the Core one leaves another dropdown alone
        #expect(shell.topMenu == .brain)
        #expect(shell.closeTopmost())
        #expect(shell.topMenu == nil)
    }
}
