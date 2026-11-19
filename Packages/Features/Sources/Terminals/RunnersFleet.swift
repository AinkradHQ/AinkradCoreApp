import CoreUI
import Shell
import SwiftUI

/// Where a runner stands, in the four words of the Runners screen (mockup 12). Only what the Core reports: a runner
/// that does not answer is "Not answering", never made out to be installing something.
enum RunnerBucket: String, CaseIterable, Identifiable, Sendable {
    case working = "Working"
    case idle = "Idle"
    /// A tool install under way (Core API minor 95): the chip says "Updating", the tile "Getting ready".
    case updating = "Getting ready"
    case attention = "Not answering"
    case offline = "Offline"
    var id: String { rawValue }
    /// The word on a runner's chip.
    var chip: String { self == .updating ? "Updating" : rawValue }

    /// An online runner that is getting its tools reads as `.updating`; offline and not answering still win.
    static func of(_ r: RunnerItem, updating: Bool) -> RunnerBucket {
        let b = RunnerBucket(of: r)
        return updating && (b == .idle || b == .working) ? .updating : b
    }

    init(of r: RunnerItem) {
        switch RunnerStatus(r) {
        case .off: self = .offline
        case .degraded: self = .attention
        case .busy: self = .working
        case .ok:
            let used = (r.slots?.agentsUsed ?? 0) + (r.slots?.terminalsUsed ?? 0)
            self = used > 0 || (r.slots == nil && r.load > 0) ? .working : .idle
        }
    }

    var symbol: String {
        switch self {
        case .working: "play.fill"
        case .idle: "pause.fill"
        case .updating: "arrow.triangle.2.circlepath"
        case .attention: "exclamationmark.triangle"
        case .offline: "power"
        }
    }

    var tone: Tone {
        switch self {
        case .working: .run
        case .idle: .queue
        case .updating: .done
        case .attention: .warn
        case .offline: .fail
        }
    }

    /// "2 are busy, 1 is not answering."; empty when there is nothing to say.
    static func sentence(_ runners: [RunnerItem], updating: Set<String> = []) -> String {
        let counts = Dictionary(grouping: runners, by: { of($0, updating: updating.contains($0.id)) }).mapValues(\.count)
        var parts: [String] = []
        if let n = counts[.working] { parts.append("\(n) \(n == 1 ? "is" : "are") busy") }
        if let n = counts[.updating] { parts.append("\(n) \(n == 1 ? "is" : "are") getting ready") }
        if let n = counts[.attention] { parts.append("\(n) \(n == 1 ? "is" : "are") not answering") }
        if let n = counts[.offline] { parts.append("\(n) \(n == 1 ? "is" : "are") offline") }
        guard let first = parts.first else { return "" }
        let rest = parts.dropFirst().map { ", " + $0 }.joined()
        let head = first.prefix(1).uppercased() + String(first.dropFirst())
        return " \(head)\(rest)."
    }
}

/// A tool a runner has, as a small rounded tag; a missing one is quiet.
struct ToolChip: View {
    let name: String
    let on: Bool
    @Environment(\.corePalette) private var palette
    var body: some View {
        Text(name).coreFont(size: MacTextSize.meta, weight: .medium).lineLimit(1).fixedSize()
            .foregroundStyle(on ? GlassInk.primary : palette.text2.opacity(0.6))
            .padding(.horizontal, Space.s2).frame(height: MacSize.chip)
            .background(on ? GlassInk.well : .clear, in: coreShape(Radius.control))
            .accessibilityLabel(on ? "\(name) ready" : "\(name) not installed")
    }
}
