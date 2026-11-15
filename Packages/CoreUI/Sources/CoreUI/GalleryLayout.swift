#if DEBUG
import SwiftUI

extension CoreUIGallery {
    // MARK: Surfaces

    @ViewBuilder var surfaces: some View {
        GSpec("coreWell", "A card inside content: a plain well, lit when active. No edge.") {
            HStack(spacing: Space.s3) {
                GVariant("Rest") { Text("A card").padding(Space.s4).frame(width: 160, alignment: .leading).coreWell() }
                GVariant("Active") {
                    Text("A card").padding(Space.s4).frame(width: 160, alignment: .leading).coreWell(active: true)
                }
            }
        }
        GSpec("coreFrame", "The glass rim of outer surfaces only: panes, dialogs, pop-ups, menus. Holds the Look.") {
            HStack(spacing: Space.s4) {
                GVariant("Pane, wide rim") {
                    Text("Pane content").padding(Space.s5).frame(width: 220, height: 100, alignment: .topLeading)
                        .coreFrame(part: .panes)
                }
                GVariant("Active") {
                    Text("Focused pane").padding(Space.s5).frame(width: 220, height: 100, alignment: .topLeading)
                        .coreFrame(active: true)
                }
                GVariant("Card, narrow rim") {
                    Text("Menu or card").padding(Space.s4).frame(width: 220, height: 100, alignment: .topLeading)
                        .coreFrame(radius: Radius.cardMac, rim: Space.s1)
                }
            }
        }
        GSpec("coreGlass, corePanel", "A clear glass control, and a material panel for content.") {
            HStack(spacing: Space.s4) {
                Label("Glass control", systemImage: "sparkles").padding(Space.s3).coreGlass()
                Text("Material panel. Content lives here.").corePanel()
            }
        }
        GSpec("CorePaneChrome", "An app's pane: icon, title, state and close, then its content.") {
            CorePaneChrome(
                title: "Terminals", sub: "linux-01", symbol: "terminal", state: ("Running", .run, "play"),
                onClose: {}
            ) {
                Text("Pane content").padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 180)
        }
        GSpec("CoreSheet", "A short form over the pane, with its footer.") {
            CoreSheet("Rename runner") {
                CoreTextField("Name", placeholder: "Runner name", text: $fieldText)
            } footer: {
                CoreDialogFooter(
                    cancel: CoreAction("Cancel", key: .cancel) {}, primary: CoreAction("Save", key: .primary) {})
            }
            .frame(maxWidth: Space.s8 * 14)
        }
        GSpec("CoreConfirmDialog", "Are you sure: one question, its answer, the way back.") {
            HStack(alignment: .top, spacing: Space.s4) {
                CoreConfirmDialog(
                    "Close this session?", message: "The AI session stops and its work is kept.", confirmTitle: "Close",
                    onConfirm: {}, onCancel: {}
                )
                .clipShape(coreShape(Radius.panel))
                CoreConfirmDialog(
                    "Delete this terminal?", message: "This cannot be undone from here.", confirmTitle: "Delete",
                    destructive: true, onConfirm: {}, onCancel: {}
                )
                .clipShape(coreShape(Radius.panel))
            }
            HStack(spacing: Space.s3) {
                Button("Open live") { confirm = true }.buttonStyle(CoreButtonStyle(.secondary))
                Button("Open destructive") { destructive = true }.buttonStyle(CoreButtonStyle(.secondary))
            }
        }
        GSpec("ConfirmCard", "A decision with several answers, each on a number key.") {
            ConfirmCard(
                title: "Where should this go?", message: "Two rooms could hold it.", symbol: "tray.2",
                choices: [
                    ConfirmChoice("Acme Shop", symbol: "folder"), ConfirmChoice("Personal", symbol: "folder"),
                    ConfirmChoice("Drop it", symbol: "trash", destructive: true),
                ], cancel: {}
            )
            .frame(maxWidth: Space.s8 * 17)
        }
        GSpec("ModalCard, ModalHeader", "A modal's card with its header and choices.") {
            VStack(alignment: .leading, spacing: Space.s3) {
                ModalHeader("Add a device", symbol: "plus.rectangle.on.rectangle", close: {})
                ModalCard(
                    title: "Sign out of this Core?", message: "This Mac forgets its keys.",
                    note: "You can pair again later.",
                    symbol: "rectangle.portrait.and.arrow.right", hue: GlassInk.red,
                    choices: [
                        (ConfirmChoice("Cancel", symbol: "xmark"), false),
                        (
                            ConfirmChoice("Sign out", symbol: "rectangle.portrait.and.arrow.right", destructive: true),
                            true
                        ),
                    ]
                )
                .frame(maxWidth: Space.s8 * 17)
            }
        }
        GSpec("CoreDialogPanel, CoreDialogFooter", "A titled panel, and the footer every dialog shares.") {
            VStack(alignment: .leading, spacing: Space.s3) {
                CoreDialogPanel("Panel title") { Text("Panel content").foregroundStyle(GlassInk.secondary) }
                CoreDialogFooter(
                    cancel: CoreAction("Cancel", key: .cancel) {}, primary: CoreAction("Delete", key: .command) {},
                    alternate: CoreAction("Keep a copy") {}, danger: true)
                CoreDialogFooter(cancel: CoreAction("Cancel") {}, primary: CoreAction("Saving") {}, busy: true)
            }
        }
    }

    // MARK: Navigation

    @ViewBuilder var navigation: some View {
        GSpec("AppHeader", "A pane's header: filters at the left, actions at the right.") {
            AppHeader {
                AppFilterTile(title: "Overview", count: -1, on: true, key: "⌘1") {}
                AppFilterTile(title: "Inbox", count: 10, on: false, key: "⌘2") {}
            } actions: {
                AppActionTile(title: "Sync now", symbol: "arrow.triangle.2.circlepath", key: "⌘R", hue: GlassInk.slate)
                {}
                AppActionTile(title: "New room", symbol: "plus", key: "⌘N", hue: GlassInk.blue, prominent: true) {}
            }
        }
        GSpec("StepTrack, CoreStepper", "Where a flow is: done, current, still to come.") {
            VStack(alignment: .leading, spacing: Space.s3) {
                StepTrack(["Sources", "Collect", "Review", "Import", "Done"], at: 2, hue: GlassInk.blue)
                CoreStepper(["Provider", "Key", "Name", "Where it goes"], at: 2, showsCount: true)
                    .frame(maxWidth: Space.s8 * 15)
            }
        }
        GSpec("GlassSection, SectionAction", "A titled settings card: icon, title, one line, an action, then content.")
        {
            GlassSection("Wallpaper", sub: "Behind every window.", symbol: "photo", hue: GlassInk.blue) {
                SectionAction("See all", symbol: "chevron.down") {}
            } content: {
                Text("Section content").foregroundStyle(GlassInk.secondary)
            }
            GlassSection("Danger zone", sub: "Cannot be undone.", symbol: "trash", hue: GlassInk.red, index: 1) {
                SectionAction("Forget", symbol: "trash", danger: true) {}
            } content: {
                EmptyView()
            }
        }
        GSpec("SettingRow, InfoRow", "A setting with its control, and a fact with its value.") {
            VStack(spacing: Space.s2) {
                SettingRow("Notify me", symbol: "bell") { CoreSwitch(isOn: $switchOn) }
                InfoRow("server.rack", "Runner", "linux-01")
                InfoRow("number", "Fingerprint", "SHA256:9f2c…", mono: true)
            }
            .frame(maxWidth: Space.s8 * 15)
        }
        GSpec("CoreRow", "A row in a list: icon, title, line, trailing state.") {
            VStack(spacing: Space.s2) {
                CoreRow(
                    "Rest", subtitle: "Leading icon, title, subtitle, trailing state", symbol: "terminal", action: {}
                ) {
                    StateBadge(SessionState.running)
                }
                CoreRow("Hover", subtitle: "Pointer over the row", symbol: "terminal", action: {}) {
                    StateBadge(RunState.queued)
                }
                .environment(\.coreForcedInteraction, .hover)
                CoreRow("Selected", subtitle: "The current row", symbol: "terminal", selected: true, action: {}) {
                    StateBadge(IssueState.inReview)
                }
                CoreRow("Disabled", subtitle: "Not available", symbol: "terminal", action: {}) {
                    StateBadge(TerminalState.exited)
                }
                .disabled(true)
            }
            .frame(maxWidth: Space.s8 * 17)
        }
    }
}
#endif
