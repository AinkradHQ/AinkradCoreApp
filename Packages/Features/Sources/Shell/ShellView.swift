import CoreUI
import SwiftUI

/// The window content: sky, Home or workspace, status cluster, and everything that opens over them.
public struct ShellView: View {
    @Bindable var shell: ShellModel
    @Environment(\.colorScheme) private var scheme
    @FocusState private var calm: Bool
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce

    public init(shell: ShellModel) { self.shell = shell }

    public var body: some View {
        ZStack {
            sky
            HomeView(shell: shell)
                .opacity(shell.surface == .home ? 1 : 0)
                .scaleEffect(shell.surface == .home || reduce ? 1 : 0.97)
                .allowsHitTesting(shell.surface == .home)
                .accessibilityHidden(shell.surface != .home)
            WorkspaceView(shell: shell)
                .opacity(shell.surface == .workspace ? 1 : 0)
                .allowsHitTesting(shell.surface == .workspace)
                .accessibilityHidden(shell.surface != .workspace)
            VStack {
                StatusCluster(shell: shell)
                Spacer(minLength: 0)
            }
            covers
            escape
        }
        .animation(reduce ? nil : Motion.out(Motion.move), value: shell.surface)
        .coreAnimation(Motion.out(Motion.ui), value: shell.coverOpen)
        .coreTheme()
        .coreToast($shell.toast)
        .sheet(item: $shell.sheet) { sheet in
            CoreSheet(sheet.title) {
                Text(sheet.message).fixedSize(horizontal: false, vertical: true)
            } footer: {
                ForEach(sheet.actions) { a in
                    Button(a.label) {
                        shell.sheet = nil
                        a.run()
                    }
                    .buttonStyle(CoreButtonStyle(a.primary ? .prominent : .secondary))
                    .keyboardShortcut(a.primary ? .defaultAction : .cancelAction)
                }
            }
        }
        // The window opens calm: focus rests on the root, so no control shows a ring until the keyboard moves it.
        .focusable()
        .focused($calm)
        .focusEffectDisabled()
        .onAppear { calm = true }
        .ignoresSafeArea()
    }

    private var sky: some View {
        Color.clear.overlay {
            Image(scheme == .dark ? "HomeSky" : "HomeSkyDay", bundle: .main).resizable().scaledToFill()
        }
        .overlay { palette.bg.opacity(shell.surface == .workspace ? 0.55 : 0).allowsHitTesting(false) }
        .clipped()
        .accessibilityHidden(true)
    }

    @ViewBuilder private var covers: some View {
        if shell.coverOpen {
            palette.bg.opacity(0.45).onTapGesture { shell.closeTopmost() }
                .transition(.opacity).accessibilityHidden(true)
        }
        if shell.launcherOpen {
            LauncherView(shell: shell).frame(maxHeight: .infinity, alignment: .center)
        }
        if shell.bellOpen {
            BellGlance(shell: shell)
                .padding(.top, ShellMetrics.topBar).padding(.trailing, Space.s4).padding(.bottom, Space.s4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        if shell.overlay == .settings { SettingsView(shell: shell) }
        if shell.overlay == .shortcuts { ShortcutsView(shell: shell) }
    }

    /// Esc closes the topmost thing, from anywhere in the window.
    private var escape: some View {
        Button("Close") { shell.closeTopmost() }
            .keyboardShortcut(.cancelAction)
            .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
    }
}
