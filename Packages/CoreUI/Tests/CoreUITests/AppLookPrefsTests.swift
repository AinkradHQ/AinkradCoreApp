import Foundation
import SwiftUI
import Testing

@testable import CoreUI

@MainActor
struct AppLookPrefsTests {
    private func suite() -> UserDefaults {
        let name = "applook-tests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test func oldTerminalKeysMoveOnce() {
        let d = suite()
        d.set(false, forKey: "terminal.followLook")
        d.set("solid", forKey: "terminal.screen")
        d.set(0.9, forKey: "terminal.opacity")
        let p = AppLookPrefs(app: "terminal", defaults: d)
        #expect(p.own && p.mode == .solid && p.opacity == 0.9)
        #expect(p.look == CoreLook(mode: .solid, opacity: 0.9, blur: p.blur))
        // The new keys now hold it, so a later change to an old key is ignored.
        d.set(true, forKey: "terminal.followLook")
        let again = AppLookPrefs(app: "terminal", defaults: d)
        #expect(again.own && again.mode == .solid)
    }

    @Test func oldBlurAndClearBecomeAMode() {
        let d = suite()
        d.set(false, forKey: "agents.followLook")
        d.set("tinted", forKey: "agents.surface")
        d.set(false, forKey: "agents.blur")
        #expect(AppLookPrefs(app: "agents", defaults: d).mode == .clear)
        let b = suite()
        b.set(false, forKey: "brain.followLook")
        b.set(true, forKey: "brain.blur")
        #expect(AppLookPrefs(app: "brain", defaults: b).mode == .blurred)
    }

    @Test func followingStaysFollowing() {
        let d = suite()
        d.set(true, forKey: "accounts.followLook")
        d.set("solid", forKey: "accounts.surface")
        let p = AppLookPrefs(app: "accounts", defaults: d)
        #expect(!p.own && p.look == nil && p.ownAccent == nil && p.palette == nil)
    }

    @Test func appsWithoutOldKeysStartAtAppearance() {
        let p = AppLookPrefs(app: "terminal", defaults: suite())
        #expect(!p.own && p.mode == LookPrefs.shared.mode && p.opacity == LookPrefs.shared.opacity)
        #expect(p.blur == LookPrefs.shared.blur)
    }

    @Test func ownAccentOnlyWhileOwn() {
        let p = AppLookPrefs(app: "lore", defaults: suite())
        p.accent = .rose
        #expect(p.ownAccent == nil)
        p.own = true
        #expect(p.ownAccent == .rose)
    }

    @Test func accentResolvesToThePanesOwnElseGlobal() {
        #expect(GlassInk.accent(.teal) == CoreAccent.teal.fill)
        #expect(GlassInk.accentInk(.teal) == CoreAccent.teal.ink)
        #expect(GlassInk.accent(nil) == AccentPrefs.shared.accent.fill)
        var palette = Palette.night
        palette.accent = .rose
        #expect(palette.btnPrimary == CoreAccent.rose.fill && palette.primary == CoreAccent.rose.ink)
        palette.accent = nil
        #expect(palette.btnPrimary == AccentPrefs.shared.accent.fill)
    }
}
