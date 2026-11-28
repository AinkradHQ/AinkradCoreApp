import CoreUI
import SwiftUI

/// The Core's start steps in order: done, the one under way, those waiting, and the one that failed with its reason.
struct StartStepsList: View {
    let steps: [StartStep]
    var body: some View {
        if !steps.isEmpty {
            VStack(alignment: .leading, spacing: Space.s1) {
                ForEach(Array(steps.enumerated()), id: \.offset) { _, s in
                    HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                        Image(systemName: symbol(s)).foregroundStyle(tint(s)).frame(width: Space.s4)
                            .coreBreathing(s.state == .active).accessibilityHidden(true)
                        Text(s.title).foregroundStyle(s.state == .pending ? GlassInk.secondary : GlassInk.primary)
                        if let d = s.detail { Text(d).foregroundStyle(GlassInk.secondary).lineLimit(2) }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(s.title), \(s.state.rawValue)\(s.detail.map { ", \($0)" } ?? "")")
                }
            }
        }
    }

    private func symbol(_ s: StartStep) -> String {
        switch s.state {
        case .done: "checkmark.square"
        case .active: "square.dotted"
        case .pending: "square"
        case .failed: "xmark.square"
        }
    }

    private func tint(_ s: StartStep) -> Color {
        switch s.state {
        case .done: GlassInk.green
        case .active: GlassInk.primary
        case .pending: GlassInk.secondary
        case .failed: GlassInk.red
        }
    }
}
