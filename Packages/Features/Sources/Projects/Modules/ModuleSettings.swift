import CoreUI
import SwiftUI

/// The Settings focused page (details v2). Contract stub: shows today's page until its lane builds the approved one.
struct ModuleSettings: View {
    let model: ProjectsModel
    let project: ProjectItem
    var body: some View { SettingsPage(model: model, project: project) }
}
