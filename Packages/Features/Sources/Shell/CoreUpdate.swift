import CoreUI
import Foundation
import SwiftUI

/// Where the Core's self-update stands (`GET /system/update`, E12-3): the words and step states of the mockup's Core pop-up.
public struct CoreUpdateStatus: Equatable, Sendable {
    public enum Phase: String, Sendable {
        case idle, snapshot, install, health, done
        case rolledBack = "rolled_back"
        case failed
    }
    public enum StepState: Sendable { case wait, now, done, fail }
    public struct Event: Equatable, Sendable {
        public var at: Date
        public var step: String
        public var text: String
    }

    public var current = ""
    public var phase = Phase.idle
    public var available: String?
    public var to: String?
    public var progress = 0.0
    public var error: String?
    public var updatedAt: Date?
    public var events: [Event] = []
    public init() {}

    public var running: Bool { [.snapshot, .install, .health].contains(phase) }

    /// The three steps in the order the updater runs them. A rolled-back run ends with the health check failed.
    public var steps: [StepState] {
        let order: [Phase] = [.snapshot, .install, .health]
        switch phase {
        case .snapshot, .install, .health:
            let at = order.firstIndex(of: phase) ?? 0
            return order.indices.map { $0 < at ? .done : $0 == at ? .now : .wait }
        case .done: return [.done, .done, .done]
        case .rolledBack: return [.done, .done, .fail]
        case .idle, .failed: return [.wait, .wait, .wait]
        }
    }

    /// Whether the Core pop-up has something to say (an update to take, one running, or the last result).
    public var visible: Bool { running || phase == .done || phase == .rolledBack || available != nil }

    /// "2 minutes" for the run's first to last event; nil with fewer than two events.
    public var tookWords: String? {
        guard let a = events.first?.at, let b = events.last?.at, b > a else { return nil }
        let m = max(1, Int((b.timeIntervalSince(a) / 60).rounded()))
        return m == 1 ? "1 minute" : "\(m) minutes"
    }

    /// Plain words for the updater's short error codes.
    public var errorWords: String {
        switch error {
        case "health_failed": "Core did not answer in time."
        case "install_failed", "wrong_version": "The new files could not be put in place."
        case "start_failed": "Core did not start."
        case "bad_signature", "bad_manifest", "manifest_replayed", "manifest_expired":
            "The update did not pass the safety check, so nothing was installed."
        case "no_manifest": "The update server could not be reached."
        default: "Something went wrong."
        }
    }

    /// The decoded answer; nil when it is not the contract's.
    public static func decode(_ data: Data) -> CoreUpdateStatus? {
        struct Wire: Decodable {
            struct E: Decodable {
                var at: Int64?
                var step: String?
                var text: String?
            }
            var current: String?
            var state: String?
            var available: String?
            var to: String?
            var progress: Double?
            var error: String?
            var updated_at: Int64?
            var events: [E]?
        }
        guard let w = try? JSONDecoder().decode(Wire.self, from: data) else { return nil }
        var s = CoreUpdateStatus()
        s.current = w.current ?? ""
        s.phase = Phase(rawValue: w.state ?? "idle") ?? .idle
        s.available = w.available
        s.to = w.to
        s.progress = min(1, max(0, w.progress ?? 0))
        s.error = w.error
        s.updatedAt = w.updated_at.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        s.events = (w.events ?? []).map {
            Event(at: Date(timeIntervalSince1970: TimeInterval($0.at ?? 0)), step: $0.step ?? "", text: $0.text ?? "")
        }
        return s
    }
}

/// The update part of the Core pop-up (mockup 04): an "Update now" row, the three steps while it runs, the result, and the
/// rolled-back card. Under Reduce Motion nothing animates; the step state is in the words and the symbol.
struct CoreUpdatePanel: View {
    let status: CoreUpdateStatus
    let update: () -> Void
    let news: () -> Void
    let what: () -> Void
    @Environment(\.corePalette) private var palette

    var body: some View {
        if status.running {
            card(
                symbol: "arrow.triangle.2.circlepath", tone: .run,
                title: "Updating Core to \(status.to ?? status.available ?? "the new version")",
                sub: "Your work keeps running. Core restarts for a few seconds."
            ) {
                stepList
                CoreMeter(status.progress, label: "Update progress")
            }
        } else if status.phase == .rolledBack {
            card(
                symbol: "exclamationmark.triangle", tone: .warn, title: "The update did not work, so we went back",
                sub: "Core is on \(status.current) again. All your data is safe."
            ) {
                stepList
                row(symbol: "arrow.uturn.backward", title: "Went back", sub: "Restored from the snapshot", state: .done)
                Text("We will try again tonight. If it keeps failing we will tell you.")
                    .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                HStack(spacing: Space.s2) {
                    Button("Try again now", action: update).buttonStyle(CoreButtonStyle(.prominent, size: .small))
                    Button("See what happened", action: what).buttonStyle(CoreButtonStyle(.secondary, size: .small))
                }
            }
        } else if status.phase == .done, let to = status.to {
            CoreNotice(
                symbol: "checkmark.circle", title: "Updated to \(to)",
                text: status.tookWords.map { "Nothing to do. It took \($0)." } ?? "Nothing to do.", tone: .done
            ) {
                Button("What is new", action: news).buttonStyle(CoreButtonStyle(.secondary, size: .small))
            }
        } else if let v = status.available {
            CoreNotice(
                symbol: "arrow.down.circle", title: "Core \(v) is ready",
                text: "It installs by itself tonight. Or update now.", tone: .queue
            ) {
                Button("Update now", action: update).buttonStyle(CoreButtonStyle(.prominent, size: .small))
            }
        }
    }

    private static let names: [(String, String, String)] = [
        ("arrow.down.to.line", "Snapshot", "A safe copy of your data, just in case"),
        ("arrow.triangle.2.circlepath", "Install", "Put the new version in place"),
        ("checkmark.seal", "Health check", "Make sure everything works"),
    ]

    private var stepList: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            ForEach(Array(Self.names.enumerated()), id: \.offset) { i, n in
                row(symbol: n.0, title: n.1, sub: n.2, state: status.steps[i])
            }
        }
    }

    private func row(symbol: String, title: String, sub: String, state: CoreUpdateStatus.StepState) -> some View {
        let tone: Tone = state == .fail ? .fail : state == .done ? .done : state == .now ? .run : .queue
        let ink = palette.tone(tone).ink
        return HStack(spacing: Space.s2) {
            Image(systemName: state == .done ? "checkmark" : state == .fail ? "xmark" : symbol)
                .coreFont(size: MacTextSize.meta, weight: .semibold).foregroundStyle(ink)
                .frame(width: Space.s6, height: Space.s6).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).coreFont(size: MacTextSize.body, weight: .medium)
                Text(sub).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
            }
            Spacer(minLength: Space.s2)
            Text(state == .done ? "Done" : state == .wait ? "Next" : state == .fail ? "Failed" : "")
                .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
        }
        .opacity(state == .wait ? 0.5 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(title), \(state == .done ? "done" : state == .wait ? "next" : state == .fail ? "failed" : "now")")
    }

    private func card<C: View>(
        symbol: String, tone: Tone, title: String, sub: String, @ViewBuilder content: () -> C
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Image(systemName: symbol).coreFont(size: MacTextSize.title).foregroundStyle(palette.tone(tone).ink)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).coreFont(size: MacTextSize.headline, weight: .semibold)
                    Text(sub).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                }
            }
            content()
        }
        .padding(Space.s3)
        .background(GlassInk.well, in: coreShape(Radius.cardMac))
        .accessibilityElement(children: .contain)
    }
}
