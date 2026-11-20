import AppKit
import CoreUI
import SwiftUI

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
    @Environment(\.coreAccent) private var paneAccent
    let text: String
    @Environment(\.planActions) private var actions

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: Space.s3) {
                IconTile("list.bullet.clipboard", hue: GlassInk.accent(paneAccent), size: MacSize.controlLg)
                Text("Plan").coreFont(size: MacTextSize.title, weight: .semibold)
                Spacer(minLength: 0)
            }
            MarkdownText(text).frame(maxWidth: .infinity, alignment: .leading)
            if let actions {
                HStack(spacing: Space.s2) {
                    Button(action: actions.goAhead) {
                        HStack(spacing: Space.s2) {
                            Text("Go Ahead")
                            Text("⌘↩").coreFont(size: MacTextSize.meta).opacity(0.7)
                        }
                    }
                    .buttonStyle(GraphiteButtonStyle())
                    .help("Approve the plan: the agent starts building it (⌘↩)").keyHint(.goAhead)
                    Button(action: actions.change) {
                        HStack(spacing: Space.s2) {
                            Text("Change Plan…")
                            Text("⇧⌘↩").coreFont(size: MacTextSize.meta).foregroundStyle(SessionInk.text2)
                        }
                    }
                    .buttonStyle(CoreButtonStyle(.secondary, size: .medium))
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
