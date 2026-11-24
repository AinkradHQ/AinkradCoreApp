import AppKit
import CoreUI
import SwiftUI

/// The Unlock card (E1-1, mockup 01): the app is blurred behind one glass card until Touch ID. It shows at open and again after the
/// Mac locks or wakes. The system Touch ID sheet (and its password fallback) comes on top when a button is pressed.
struct UnlockCard: View {
    @Environment(\.coreAccent) private var paneAccent
    @Bindable var shell: ShellModel
    /// The Touch ID sheet is up: only the frosted backdrop shows under it, never a second card (Ahmed, 2026-11-21: the
    /// sheet looks better, and two surfaces read as "still locked after I scanned").
    var sheetUp = false
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var breathe = false
    /// When the last ask ended unanswered: the system Touch ID panel takes focus, so Cancel makes the app active again;
    /// that comeback must not ask again (no loop). A later, real return to the app does.
    @State private var askEnded = Date.distantPast

    private var checking: Bool { shell.lock == .checking }

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).opacity(0.96)
                .overlay(Color.black.opacity(0.18))
                .ignoresSafeArea()
                .accessibilityHidden(true)
            if !sheetUp { card }
        }
        .onAppear {
            // Locked means Touch ID now: the sheet comes up by itself, no button first. Cancelling it leaves this card
            // (its buttons ask again); it is asked once per lock, never in a loop.
            if shell.lock == .locked, NSApplication.shared.isActive { shell.unlock?() }
            guard !reduce else { return }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { breathe = true }
        }
        // The card often appears while Ainkrad is in the background (the Mac woke, the app relaunched, it locked while
        // another app was in front): ask the moment it comes to the front, so unlocking is one step, the finger
        // (Ahmed, 2026-11-24). Cancel leaves the card; the next time the app comes to the front it asks again.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if shell.lock == .locked, Date().timeIntervalSince(askEnded) > 2 { shell.unlock?() }
        }
        .onChange(of: shell.lock) { was, now in
            if was == .checking, now == .locked { askEnded = Date() }
        }
        .transition(.opacity)
    }

    /// The same card as the Touch ID sheet (StepUpSheet): the tile with its halos, "Touch the sensor", one quiet action
    /// (Ahmed, 2026-11-21: the sheet's style is much better). The sheet itself replaces it while Touch ID is asked.
    private var card: some View {
        VStack(spacing: Space.s4) {
            ZStack {
                if !reduce {
                    ForEach(0..<2, id: \.self) { i in
                        coreShape(Radius.pane).stroke(GlassInk.accent(paneAccent).opacity(0.35), lineWidth: 1.5)
                            .frame(width: 112, height: 112)
                            .coreScaleEffect(1 + CGFloat(i + 1) * 0.16)
                            .opacity(breathe ? 0.9 : 0.4)
                    }
                }
                coreShape(Radius.pane).fill(GlassInk.accent(paneAccent).opacity(0.4))
                    .frame(width: 112, height: 112)
                VStack(spacing: Space.s1) {
                    Image(systemName: "touchid").font(.system(size: 44, weight: .light))
                        .symbolEffect(.pulse, options: .repeating, isActive: checking && !reduce)
                    Text("Touch ID").coreFont(size: MacTextSize.body)
                }
                .foregroundStyle(GlassInk.primary)
            }
            .frame(width: 170, height: 170)
            .accessibilityHidden(true)
            VStack(spacing: Space.s2) {
                Text(checking ? "Checking…" : "Touch the sensor")
                    .coreFont(size: MacTextSize.large + 6, weight: .bold)
                    .contentTransition(.opacity)
                    .accessibilityAddTraits(.isHeader)
                Text("Unlock Ainkrad.").foregroundStyle(GlassInk.secondary)
            }
            Button("Use Touch ID") { shell.unlock?() }
                .buttonStyle(CoreButtonStyle(.plain))
                .coreShortcut(.primary)
                .disabled(checking)
            HStack(spacing: Space.s2) {
                Image(systemName: "lock").accessibilityHidden(true)
                Text("Stays open until your Mac locks or sleeps").coreFont(size: MacTextSize.body, weight: .semibold)
            }
            .foregroundStyle(GlassInk.secondary)
        }
        .foregroundStyle(GlassInk.primary)
        .padding(Space.s6)
        .frame(width: Space.s8 * 13)
        .corePanel(radius: Radius.pane + Space.s1, padding: 0)
        .shadow(color: GlassInk.shade(0.35), radius: 40, y: 16)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Unlock Ainkrad")
        .accessibilityIdentifier("unlock")
    }
}
