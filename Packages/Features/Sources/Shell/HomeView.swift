import CoreUI
import SwiftUI

/// Home: the sky with the widget desk. Left and right columns of fixed-size glass widgets, the greeting between them.
struct HomeView: View {
    @Bindable var shell: ShellModel
    @Environment(\.corePalette) private var palette

    private static let left: [[WidgetKind]] = [[.today], [.clock, .spend], [.quick]]
    private static let right: [[WidgetKind]] = [[.machines], [.board], [.events]]

    var body: some View {
        ZStack(alignment: .top) {
            HStack(alignment: .top) {
                column(Self.left)
                Spacer(minLength: Space.s8)
                column(Self.right)
            }
            .padding(.horizontal, ShellMetrics.widgetInset)
            .padding(.top, ShellMetrics.topBar)
            greeting.frame(maxHeight: .infinity, alignment: .center).padding(.bottom, Space.s8 * 4)
            controls.frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, Space.s5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func column(_ rows: [[WidgetKind]]) -> some View {
        VStack(alignment: .leading, spacing: ShellMetrics.widgetGap) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                let kinds = row.filter { !shell.hiddenWidgets.contains($0) }
                if !kinds.isEmpty {
                    HStack(spacing: ShellMetrics.widgetGap) {
                        ForEach(kinds) { kind in
                            WidgetCard(kind: kind, shell: shell, size: size(kind))
                                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        }
                    }
                }
            }
        }
    }

    private func size(_ kind: WidgetKind) -> (cols: Int, rows: Int) {
        switch kind {
        case .today: (2, 3)
        case .clock, .spend: (1, 1)
        case .quick, .board, .events: (2, 1)
        case .machines: (2, 2)
        }
    }

    private var greeting: some View {
        VStack(spacing: Space.s2) {
            Text(shell.home.greetingName.map { "\(Self.dayPart), \($0)" } ?? Self.dayPart)
                .font(.system(size: MacTextSize.large * 1.6, weight: .semibold))
            HStack(spacing: Space.s2) {
                Text("Press")
                CoreKeycap("⌘K")
                Text("to open the launcher.")
            }
            .foregroundStyle(palette.text2)
        }
        .accessibilityElement(children: .combine)
    }

    private static var dayPart: String {
        let h = Calendar.current.component(.hour, from: Date())
        return h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening"
    }

    private var controls: some View {
        HStack(spacing: Space.s1) {
            Button {
                shell.addingWidget = true
            } label: {
                Label("Add Widget", systemImage: "plus")
            }
            Button {
                shell.editingWidgets.toggle()
            } label: {
                Label(shell.editingWidgets ? "Done" : "Edit Widgets", systemImage: "slider.horizontal.3")
            }
        }
        .buttonStyle(CoreButtonStyle(.plain, size: .small))
        .padding(Space.s1)
        .coreGlass(radius: Radius.cardMac)
        .sheet(isPresented: $shell.addingWidget) { AddWidgetSheet(shell: shell) }
    }
}

private struct AddWidgetSheet: View {
    @Bindable var shell: ShellModel
    var body: some View {
        CoreSheet("Add Widget") {
            VStack(spacing: Space.s2) {
                let hidden = WidgetKind.allCases.filter { shell.hiddenWidgets.contains($0) }
                ForEach(hidden) { kind in
                    CoreRow(kind.title, subtitle: kind.about, symbol: kind.symbol) {
                        shell.restoreWidget(kind)
                        if shell.hiddenWidgets.isEmpty { shell.addingWidget = false }
                    }
                }
                if hidden.isEmpty { Text("Every widget is already on Home.") }
            }
        } footer: {
            Button("Done") { shell.addingWidget = false }.buttonStyle(.coreProminent).keyboardShortcut(.defaultAction)
        }
    }
}
