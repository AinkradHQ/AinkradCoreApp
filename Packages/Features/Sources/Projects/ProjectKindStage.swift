import CoreUI
import SwiftUI

/// Project Settings: what the project is. Changing it changes the pages and buttons the project shows; nothing else.
struct KindSettings: View {
    let model: ProjectsModel
    let project: ProjectItem

    var body: some View {
        Island("What it is") {
            VStack(alignment: .leading, spacing: Space.s2) {
                CoreSelect(
                    "Kind", selection: Binding(get: { project.kind }, set: { model.setKind($0, for: project) }),
                    options: ProjectKind.allCases.map { CoreSelectOption($0, $0.title, symbol: $0.symbol) }
                )
                .disabled(model.readOnly)
                .help(model.readOnly ? "This device can look at projects but not change them." : "")
                Text(project.kind.line).foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
                if !model.core111 {
                    Text("Saved on this Mac only.")
                        .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityIdentifier("project-settings-kind")
    }
}
