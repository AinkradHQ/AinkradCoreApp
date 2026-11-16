import AppKit
import CoreUI
import SwiftUI

/// A sub-agent the session started (Task / Agent tool): its kind and job, working or done, the brief it was given and its
/// report, both folded until opened. Gallery parts only: a card, an icon tile, a state badge.
struct SubAgentCard: View {
    let type: String
    let task: String
    let prompt: String
    let result: String?
    let ok: Bool?
    let durationMs: Int?
    @State private var open = false

    private var state: (String, Tone, String) {
        switch ok {
        case nil: ("Working", .run, "ellipsis")
        case true?: ("Done", .done, "checkmark")
        case false?: ("Failed", .fail, "xmark")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Button {
                withAnimation(Motion.out(Motion.ui)) { open.toggle() }
            } label: {
                HStack(spacing: Space.s3) {
                    IconTile("person.2", hue: GlassInk.blue, size: MacSize.controlLg)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task).coreFont(size: MacTextSize.body, weight: .semibold).lineLimit(2)
                        Text(
                            "Sub-agent · \(type)"
                                + (durationMs.map { " · \(coreDecimal(Double($0) / 1000, 1)) s" } ?? "")
                        )
                        .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                    }
                    Spacer(minLength: Space.s2)
                    StateBadge(state.0, tone: state.1, symbol: state.2)
                    Image(systemName: "chevron.right").coreFont(size: MacTextSize.meta, weight: .semibold)
                        .foregroundStyle(GlassInk.secondary).rotationEffect(.degrees(open ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Sub-agent: \(task), \(state.0)")
            if open {
                if !prompt.isEmpty {
                    Text("Brief").coreFont(size: MacTextSize.meta, weight: .semibold).foregroundStyle(
                        GlassInk.secondary)
                    MarkdownText(prompt).padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
                        .background(GlassInk.well, in: coreShape(Radius.control))
                }
                if let result, !result.isEmpty {
                    Text("Report").coreFont(size: MacTextSize.meta, weight: .semibold).foregroundStyle(
                        GlassInk.secondary)
                    MarkdownText(result).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
        .sessionSurface(radius: Radius.cardMac)
        .agentCopyMenu(result ?? prompt)
    }
}

/// What a plan card can do in the open session (set by SessionView): go ahead with the plan, or start a change to it.
struct PlanActions {
    var goAhead: () -> Void
    var change: () -> Void
}

extension EnvironmentValues {
    @Entry var planActions: PlanActions? = nil
}

/// A plan the agent proposes (ExitPlanMode): titled, its Markdown in full (headings, steps, tables, code), and in a live
/// session Go ahead / Change it.
struct PlanCard: View {
    let text: String
    @Environment(\.planActions) private var actions

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: Space.s3) {
                IconTile("list.bullet.clipboard", hue: GlassInk.blue, size: MacSize.controlLg)
                Text("Plan").coreFont(size: MacTextSize.title, weight: .semibold)
                Spacer(minLength: 0)
            }
            MarkdownText(text).frame(maxWidth: .infinity, alignment: .leading)
            if let actions {
                HStack(spacing: Space.s2) {
                    Button("Go ahead", action: actions.goAhead)
                        .buttonStyle(CoreButtonStyle(.prominent, size: .small))
                        .help("Approve the plan: the agent starts building it (⌘↩)").keyHint(.goAhead)
                    Button("Change it", action: actions.change)
                        .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                        .help("Write what to change in the plan (⇧⌘↩)").keyHint(.changePlan)
                }
            }
        }
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
        .sessionSurface(radius: Radius.cardMac)
        .agentCopyMenu(text)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Plan")
    }
}

/// What a person's message attached (`@path` at its end): images as thumbnails, other files as chips. Only files this Mac
/// can see are drawn as pictures; others show their name.
enum MessageFiles {
    static let imageTypes: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "webp", "tiff"]

    /// The words and the attached paths of a message (paths are `@/...` tokens).
    static func split(_ text: String) -> (words: String, files: [String]) {
        var words: [Substring] = []
        var files: [String] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let tokens = line.split(separator: " ")
            if !tokens.isEmpty, tokens.allSatisfy({ $0.hasPrefix("@/") }) {
                files += tokens.map { String($0.dropFirst()) }
            } else {
                words.append(line)
            }
        }
        return (words.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines), files)
    }
}

struct MessageFilesView: View {
    let paths: [String]

    var body: some View {
        HStack(spacing: Space.s2) {
            ForEach(paths, id: \.self) { p in
                let url = URL(fileURLWithPath: p)
                if MessageFiles.imageTypes.contains(url.pathExtension.lowercased()), let img = NSImage(contentsOf: url)
                {
                    Image(nsImage: img).resizable().scaledToFill()
                        .frame(width: Space.s8 * 4, height: Space.s8 * 3)
                        .clipShape(coreShape(Radius.cardMac))
                        .help(p)
                        .accessibilityLabel("Image \(url.lastPathComponent)")
                } else {
                    CoreChip(url.lastPathComponent, symbol: "doc", minWidth: 0).help(p)
                }
            }
        }
    }
}
