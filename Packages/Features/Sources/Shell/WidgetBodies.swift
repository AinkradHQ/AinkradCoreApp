import CoreUI
import SwiftUI

/// The content of each widget at each macOS size (N9): small, medium, large and extra large each have their own layout with
/// more data, not the same layout with more room. A header, one large figure, and a bar or chart only where it shows real
/// progress or data. What the Core does not report is left out, never shown as filler (Ahmed, 2026-11-15).
struct WidgetBody: View {
    let kind: WidgetKind
    let size: WidgetSize
    @Bindable var shell: ShellModel

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private var content: some View {
        switch kind {
        case .today: TodayBody(shell: shell, size: size)
        case .needs: NeedsBody(shell: shell, size: size)
        case .running: RunningBody(shell: shell, size: size)
        case .spend: SpendBody(home: shell.home, size: size)
        case .machines: MachinesBody(home: shell.home, size: size)
        case .board: BoardBody(board: shell.home.board, size: size)
        case .events: EventsBody(home: shell.home, size: size)
        case .core: CoreBody(shell: shell, size: size)
        case .quick: QuickBody(shell: shell, size: size)
        case .clock: AnalogClockBody(size: size)
        case .digital: DigitalClockBody(size: size)
        case .terminals: TerminalsBody(home: shell.home, size: size)
        case .projects: ProjectsBody(home: shell.home, size: size)
        case .brain: BrainBody(shell: shell, size: size)
        case .todaynote: TodayNoteBody(shell: shell, size: size)
        case .approvals: ApprovalsBody(shell: shell, size: size)
        case .aiusage: AIUsageBody(home: shell.home, size: size)
        case .weather: WeatherBody(size: size)
        case .calendar: CalendarBody(size: size)
        }
    }
}

extension HomeSnapshot {
    var totalSlots: Int { machines.reduce(0) { $0 + $1.slots } }
}
