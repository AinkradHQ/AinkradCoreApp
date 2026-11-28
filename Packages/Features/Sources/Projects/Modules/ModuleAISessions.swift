import CoreUI
import SwiftUI

/// The AISessions focused page (details v2). Contract stub: shows today's page until its lane builds the approved one.
struct ModuleAISessions: View {
    let model: ProjectsModel
    let project: ProjectItem
    var body: some View { SessionsPage(model: model, project: project) }
}
