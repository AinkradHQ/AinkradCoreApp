import CoreUI
import Foundation
import SwiftUI

/// Where a job (or an AI session) ran, as the Core placed it (E15 §5, `Job.place_reason`).
public struct JobPlace: Equatable, Sendable {
    public enum Reason: String, Sendable {
        case core, overflow, runner, thisMac = "this_mac", coreNoFit = "core_no_fit", pinned
    }
    public var deviceName: String
    public var reason: Reason
    /// With `coreNoFit`: what no other machine had (`xcode`, `os macos`).
    public var missing: String?
    /// `Job.state`: `queued`, `syncing`, `running`, `ended`, `failed`, `cancelled`, `lost`. A session has none: `ended`.
    public var state: String

    public init(deviceName: String, reason: Reason, missing: String? = nil, state: String = "ended") {
        self.deviceName = deviceName
        self.reason = reason
        self.missing = missing
        self.state = state
    }

    var live: Bool { ["queued", "syncing", "running"].contains(state) }

    /// "Ran on Build box", "Running on This Mac"; nil when it ran on the Core by default, which needs no chip.
    public var words: String? {
        if reason == .core { return nil }
        let name = reason == .coreNoFit ? "Core" : deviceName
        let verb = state == "lost" ? "Lost on" : live ? "Running on" : "Ran on"
        return "\(verb) \(name)"
    }

    /// The reason, in a sentence, for the tooltip.
    public var why: String {
        switch reason {
        case .core: "It ran on the Core."
        case .overflow: "The Core was full, so \(deviceName) took it."
        case .runner: "\(deviceName) took it as a heavy job."
        case .thisMac: "It ran on This Mac."
        case .coreNoFit: "No other machine had \(missing ?? "what it needed"), so it ran on the Core."
        case .pinned: "Its sign-in lives on \(deviceName), so it ran there."
        }
    }

    var symbol: String { reason == .thisMac ? "laptopcomputer" : "server.rack" }
}

/// "Ran on X": a quiet chip on AI sessions, terminals and project runs that did not run on the Core by default. Nothing
/// for a Core run, nothing before the Core reports hardware. Symbol and words, never colour alone; it has no motion.
public struct RanOnChip: View {
    let place: JobPlace?
    @Environment(\.corePalette) private var palette
    public init(_ place: JobPlace?) { self.place = place }

    public var body: some View {
        if let place, let words = place.words {
            Label(words, systemImage: place.symbol)
                .coreFont(size: MacTextSize.meta, weight: .medium)
                .foregroundStyle(palette.text2)
                .padding(.horizontal, Space.s2).frame(minHeight: MacSize.chip)
                .background(palette.uDim, in: coreShape(Radius.chip))
                .lineLimit(1).fixedSize()
                .help(place.why)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(words)
                .accessibilityHint(place.why)
        }
    }
}

/// How long a pause lasts, from the top bar's menu and a machine's page.
public enum PauseSpan: Equatable, Sendable {
    case hour, tomorrow, indefinite, resume

    /// The instant the pause ends; nil lifts it. "Indefinitely" is the year 2100, which the Core reads as no end.
    public func until(now: Date = .now, calendar: Calendar = .current) -> Date? {
        switch self {
        case .hour: return now.addingTimeInterval(3600)
        case .tomorrow:
            let next = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
            return calendar.date(byAdding: .hour, value: 6, to: next)
        case .indefinite: return Self.forever
        case .resume: return nil
        }
    }
    public static let forever = Date(timeIntervalSince1970: 4_102_444_800)
    public static func isForever(_ d: Date) -> Bool { d >= forever.addingTimeInterval(-86_400) }
}

/// What the top bar, session headers, terminals and project runs read about hardware. The Terminals feature fills it from
/// `/hardware`, `/hardware/pool` and `/jobs`; `bar == nil` means the Core has no hardware API (before minor 95, or `/hardware`
/// did not answer 200), and then nothing hardware-related shows anywhere.
@MainActor @Observable
public final class HardwareDeck {
    public struct Bar: Equatable, Sendable {
        public var loadPct: Int
        public var paused: Bool
        public var jobs: Int
        public var sessions: Int
        public var macs: [Mac]
        public init(loadPct: Int, paused: Bool, jobs: Int, sessions: Int, macs: [Mac]) {
            self.loadPct = loadPct
            self.paused = paused
            self.jobs = jobs
            self.sessions = sessions
            self.macs = macs
        }
    }
    /// A machine the menu can pause by itself: not the Core.
    public struct Mac: Equatable, Sendable, Identifiable {
        public var id: String
        public var name: String
        public var paused: Bool
        public init(id: String, name: String, paused: Bool) {
            self.id = id
            self.name = name
            self.paused = paused
        }
    }

    public var bar: Bar?
    public var jobByTerminal: [String: JobPlace] = [:]
    public var jobBySession: [String: JobPlace] = [:]
    public var jobByProject: [Int: JobPlace] = [:]
    /// Runner id to name, for every machine that is not the Core: a session on one of them overflowed or is pinned there.
    public var offCore: [String: String] = [:]
    /// Pauses one machine (`nil`: all) for a span. The Terminals feature owns the Core call and Touch ID.
    public var pause: (@MainActor (_ device: String?, _ span: PauseSpan) -> Void)?
    /// Opens the Hardware app.
    public var open: (@MainActor () -> Void)?

    public init() {}
    public var on: Bool { bar != nil }

    /// A session's place: its newest job's, else "ran on X" when its runner is not the Core.
    public func place(session id: String, runner: String) -> JobPlace? {
        if let p = jobBySession[id] { return p }
        return offCore[runner].map { JobPlace(deviceName: $0, reason: .runner) }
    }
}
