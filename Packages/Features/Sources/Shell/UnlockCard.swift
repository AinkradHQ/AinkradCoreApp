import CoreUI
import SwiftUI

/// The Unlock card (E1-1, mockup 01): the app is blurred behind one glass card until Touch ID. It shows at open and again after the
/// Mac locks or wakes. The system Touch ID sheet (and its password fallback) comes on top when a button is pressed.
struct UnlockCard: View {
    @Bindable var shell: ShellModel
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.corePalette) private var palette
    @State private var breathe = false

    private var checking: Bool { shell.lock == .checking }

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).opacity(0.96)
                .overlay(Color.black.opacity(0.18))
                .ignoresSafeArea()
                .accessibilityHidden(true)
            VStack(spacing: Space.s2) {
                ZStack {
                    coreShape(Radius.pane).fill(GlassInk.blue.opacity(checking ? 0.3 : breathe ? 0.34 : 0.18))
                        .frame(width: 96, height: 96)
                    Image(systemName: "touchid").font(.system(size: 48, weight: .light))
                        .foregroundStyle(GlassInk.blue)
                        .symbolEffect(.pulse, options: .repeating, isActive: checking && !reduce)
                }
                .padding(.top, Space.s1).padding(.bottom, Space.s3)
                .accessibilityHidden(true)
                Text("Unlock Ainkrad").coreFont(size: MacTextSize.large + 4, weight: .bold)
                    .accessibilityAddTraits(.isHeader)
                Text(checking ? "Checking…" : "Touch the sensor to open your Core")
                    .coreFont(size: MacTextSize.body).foregroundStyle(palette.text2)
                    .contentTransition(.opacity)
                Button {
                    shell.unlock?()
                } label: {
                    Label("Use Touch ID", systemImage: "touchid")
                }
                .buttonStyle(CoreButtonStyle(.prominent))
                .coreShortcut(.primary)
                .disabled(checking)
                .padding(.top, Space.s3)
                Button("Use password instead") { shell.unlock?() }
                    .buttonStyle(CoreButtonStyle(.plain))
                    .disabled(checking)
                HStack(spacing: Space.s1) {
                    Image(systemName: "lock").accessibilityHidden(true)
                    Text("Stays open until your Mac locks or sleeps")
                }
                .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                .padding(.top, Space.s3)
            }
            .padding(.horizontal, Space.s6).padding(.vertical, Space.s6)
            .frame(width: Space.s8 * 8)
            .corePanel(radius: Radius.pane + Space.s1, padding: 0)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Unlock Ainkrad")
            .accessibilityIdentifier("unlock")
        }
        .onAppear {
            guard !reduce else { return }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { breathe = true }
        }
        .transition(.opacity)
    }
}
