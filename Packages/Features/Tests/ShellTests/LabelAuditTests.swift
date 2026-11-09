import Foundation
import SwiftUI
import Testing

@testable import Shell

/// Accessibility label audit (A-29): the words VoiceOver reads for Home widgets, launcher entries and pane tabs.
@MainActor
struct LabelAuditTests {
    @Test func everyWidgetKindAndSizeHasAName() {
        for k in WidgetKind.allCases {
            #expect(!k.title.isEmpty && !k.about.isEmpty, "\(k) has no name")
        }
        for s in WidgetSize.allCases { #expect(!s.title.isEmpty, "\(s) has no name") }
    }

    @Test func everyLauncherEntryAndPaneTabIsNamed() {
        let shell = ShellModel()
        SampleWorld.install(into: shell)
        #expect(!shell.launcher.entries.isEmpty)
        for e in shell.launcher.entries { #expect(!e.title.isEmpty, "launcher entry \(e.id) has no title") }
        for id in ["agents", "terminals", "runners", "core"] {
            let spec = SampleWorld.samplePane(id, shell)
            #expect(!shell.tabName(spec).isEmpty, "pane \(id) has no tab name")
        }
    }
}
