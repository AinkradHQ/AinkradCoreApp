#if DEBUG
import SwiftUI

extension CoreUIGallery {
    /// Every core control on one screen, so one capture shows a whole style (an accent, a wallpaper, a theme, a scenario),
    /// then the worst case: long words, huge counts, nothing at all.
    @ViewBuilder var styles: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: Space.s4, alignment: .top), GridItem(.flexible(), alignment: .top),
            ],
            alignment: .leading, spacing: Space.s4
        ) {
            GSpec("Actions", "Buttons, header tiles and filters.") {
                VStack(alignment: .leading, spacing: Space.s3) {
                    HStack(spacing: Space.s2) {
                        Button("Save") {}.buttonStyle(CoreButtonStyle(.prominent))
                        Button("Cancel") {}.buttonStyle(CoreButtonStyle(.secondary))
                        Button("More") {}.buttonStyle(CoreButtonStyle(.plain))
                        Button("Delete") {}.buttonStyle(CoreButtonStyle(.danger))
                        Button("Off") {}.buttonStyle(CoreButtonStyle(.prominent)).disabled(true)
                    }
                    HStack(spacing: Space.s2) {
                        AppFilterTile(title: "Rooms", count: 9, on: true, key: "⌘1") {}
                        AppFilterTile(title: "Inbox", count: 10, on: false, key: "⌘2") {}
                        AppActionTile(title: "New room", symbol: "plus", key: "⌘N", hue: GlassInk.blue, prominent: true)
                        {}
                    }
                }
            }
            GSpec("Choices", "Switches, checkboxes, segments, selects.") {
                VStack(alignment: .leading, spacing: Space.s3) {
                    HStack(spacing: Space.s4) {
                        CoreSwitch("On", isOn: $switchOn)
                        CoreSwitch("Off", isOn: $switchOff)
                        CoreCheckbox("read", isOn: checkBinding("read"), mono: true)
                    }
                    CoreSegmented(
                        "Filter",
                        segments: [
                            CoreSegment("all", "All"), CoreSegment("run", "Running"), CoreSegment("done", "Done"),
                        ],
                        selection: $segment)
                    CoreSelect(nil, selection: $selectPick, options: Self.selectOptions).frame(width: Space.s8 * 7)
                }
            }
            GSpec("Fields", "Filled, empty and wrong.") {
                VStack(alignment: .leading, spacing: Space.s3) {
                    CoreTextField("Name", placeholder: "Device name", text: $fieldText)
                    CoreTextField("Empty", placeholder: "Device name", text: $emptyText)
                    CoreTextField(
                        "Error", placeholder: "Device name", text: $fieldText, error: "Use 1 to 64 characters.")
                }
            }
            GSpec("Status", "States, counts, chips and tiles.") {
                VStack(alignment: .leading, spacing: Space.s3) {
                    HStack(spacing: Space.s3) {
                        StateBadge("Running", tone: .run, symbol: "play")
                        StateBadge("Needs you", tone: .warn, symbol: "hand.raised")
                        StateBadge("Failed", tone: .fail, symbol: "xmark")
                        StateBadge("Done", tone: .done, symbol: "checkmark")
                        StateBadge("Queued", tone: .queue, symbol: "clock")
                    }
                    HStack(spacing: Space.s3) {
                        CountBadge(3)
                        CountBadge(2, tone: .needsYou)
                        CountBadge(12, tone: .quiet)
                        CoreChip("Cloud")
                        IconTile("server.rack", hue: GlassInk.blue)
                        IconTile("exclamationmark.triangle", hue: GlassInk.amber)
                    }
                }
            }
            GSpec("Lists", "Rows at rest, hovered and selected.") {
                VStack(spacing: Space.s2) {
                    CoreRow("linux-01", subtitle: "2 of 4 AI sessions", symbol: "server.rack", action: {}) {
                        StateBadge("Online", tone: .run, symbol: "checkmark")
                    }
                    CoreRow("home-server", subtitle: "Hover", symbol: "server.rack", action: {}) {
                        StateBadge("Online", tone: .run, symbol: "checkmark")
                    }
                    .environment(\.coreForcedInteraction, .hover)
                    CoreRow("mac-studio", subtitle: "Selected", symbol: "laptopcomputer", selected: true, action: {}) {
                        StateBadge("Busy", tone: .warn, symbol: "hourglass")
                    }
                }
            }
            GSpec("Messages and data", "A notice, a limit and a trend.") {
                VStack(alignment: .leading, spacing: Space.s3) {
                    CoreNotice(
                        symbol: "hand.raised", title: "An approval waits", text: "Claude wants to push.", tone: .warn)
                    CoreMeter(0.77, label: "Used")
                    CoreMeter(0.95, low: true, label: "Near the limit")
                    HStack(spacing: Space.s4) {
                        CoreSpark([3, 5, 2, 7, 4, 6, 8]).frame(width: 120, height: 24)
                        CoreSlots(used: 2, capacity: 4)
                    }
                }
            }
        }
        GSpec("Worst case", "Long words, huge counts, nothing at all: nothing may overflow, overlap or hide its state.")
        {
            VStack(alignment: .leading, spacing: Space.s3) {
                CoreRow(
                    "A very long AI session title that keeps going well past the edge of any row it sits in",
                    subtitle: "claude-code on a-runner-with-an-unusually-long-hostname.internal.example.com",
                    symbol: "text.cursor", action: {}
                ) {
                    StateBadge("Waiting for an approval from you", tone: .warn, symbol: "hand.raised")
                }
                HStack(spacing: Space.s3) {
                    CountBadge(1284)
                    CountBadge(99_999, tone: .needsYou)
                    CoreChip("an-unbreakable-identifier-without-any-spaces-at-all")
                    Button("A button whose label is much longer than it should be") {}
                        .buttonStyle(CoreButtonStyle(.secondary))
                }
                HStack(alignment: .top, spacing: Space.s4) {
                    CoreTextField(
                        "A label that is long enough to wrap onto a second line in a narrow form",
                        placeholder: "Nothing typed yet", text: $emptyText,
                        error: "A long error that explains exactly what went wrong and how to put it right.")
                    CoreStateCard(
                        symbol: "tray", title: "Nothing here yet", line: "Sessions you start show up here.",
                        primary: CoreAction("New session") {})
                }
            }
        }
    }
}
#endif
