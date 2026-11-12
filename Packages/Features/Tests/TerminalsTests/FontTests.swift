import AppKit
import Foundation
import Testing

@testable import Terminals

@MainActor
struct FontTests {
    @Test func theBundledNerdFontRegistersAndShipsItsLicence() throws {
        TerminalFonts.register()
        #expect(NSFont(name: TerminalFonts.family, size: 12) != nil)
        #expect(TerminalPrefs.families.first == TerminalFonts.family)
        let dir = try #require(Bundle.module.resourceURL)
        let names = try FileManager.default.subpathsOfDirectory(atPath: dir.path)
        #expect(names.contains { $0.hasSuffix("MesloLGS-NF-LICENSE.txt") })
    }
}
