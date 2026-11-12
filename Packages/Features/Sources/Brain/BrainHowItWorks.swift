import CoreUI
import Shell
import SwiftUI

/// "How the Brain works": one page, plain words. The text is data so a test can read it and the other screens can quote it.
public enum BrainHowItWorks {
    public struct Section: Identifiable, Sendable {
        public var id: String { title }
        public let title: String
        public let text: String
    }

    public static let sections: [Section] = [
        Section(
            title: "What it keeps",
            text: "Decisions, facts, preferences, landmines and open threads that your AI sessions learn, "
                + "each with the sources it came from. It keeps what is worth remembering, not every word."),
        Section(
            title: "Rooms",
            text: "Memory lives in rooms, and a room is sealed apart from every other. Employers and clients "
                + "never share a room, so something from one can never turn up in another."),
        Section(
            title: "Touch ID on every room open",
            text: "Opening a room asks for Touch ID each time. The key is lent for a while and then the room seals "
                + "again by itself."),
        Section(
            title: "What is never imported",
            text: "Passwords, keys, certificates and contracts are never read. Projects you have refused "
                + "(GitScope, Finvo, Habtic, ILINK and JoseOs) are skipped too, and nothing of them is stored."),
        Section(
            title: "Where it lives",
            text: "On your Core, encrypted with one key. Every room is kept there. Nothing is stored until you "
                + "press Import accepted rooms."),
        Section(
            title: "Which models may read a room",
            text: "Sorting what you import into rooms uses no model at all. Later, the approved cloud provider may "
                + "read any room, and you can set one room to local models only."),
    ]

    /// Opens the page over the shell.
    @MainActor public static func open(_ shell: ShellModel) {
        shell.present(
            ShellDialog(id: "brain-how") {
                HowBrainWorksSheet { shell.closeDialog() }
            })
    }
}

struct HowBrainWorksSheet: View {
    let close: () -> Void
    var body: some View {
        CoreDialogPanel("How the Brain works", width: Space.s8 * 18) {
            VStack(alignment: .leading, spacing: Space.s3) {
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.s3) {
                        ForEach(BrainHowItWorks.sections) { s in
                            VStack(alignment: .leading, spacing: Space.s1) {
                                Text(s.title).coreFont(size: MacTextSize.headline, weight: .semibold)
                                    .accessibilityAddTraits(.isHeader)
                                Text(s.text).foregroundStyle(GlassInk.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .frame(maxHeight: Space.s8 * 16)
                CoreDialogFooter(cancel: nil, primary: CoreAction("Done", key: .primary, run: close))
            }
        }
        .accessibilityIdentifier("brain-how")
    }
}

/// A tab the Core does not serve yet.
struct BrainComingLater: View {
    let title: String
    var body: some View {
        BrainStateCard(
            symbol: "clock", title: "\(title) comes later",
            text: "This part of the Brain is not built yet. Importing and rooms work now."
        )
        .accessibilityIdentifier("brain-coming-later")
    }
}

/// The Overview of a real Core: what is stored, in numbers. The health charts are for the sample until Core serves them.
struct CoreOverviewTab: View {
    let model: BrainModel
    var body: some View {
        let sources = model.rooms.reduce(0) { $0 + ($1.counts?.records ?? 0) }
        VStack(alignment: .leading, spacing: Space.s3) {
            BrainCard(
                "Your Brain",
                sub: "\(BrainWords.plural(model.rooms.count, "room", "rooms")) on your Core, "
                    + "\(BrainWords.plural(sources, "source", "sources")) stored."
            ) {
                HStack(spacing: Space.s2) {
                    Button("Import more") { model.openImport() }.buttonStyle(CoreButtonStyle(.prominent, size: .small))
                    Button("How it works") { BrainHowItWorks.open(model.host.shell) }
                        .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                }
            }
        }
        .accessibilityIdentifier("brain-overview-core")
    }
}
