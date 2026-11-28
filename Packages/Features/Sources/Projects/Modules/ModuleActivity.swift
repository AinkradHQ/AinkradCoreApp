import CoreUI
import SwiftUI

/// The Activity focused page (details v2). Contract stub: shows today's page until its lane builds the approved one.
struct ModuleActivity: View {
    let model: ProjectsModel
    let project: ProjectItem
    var body: some View { Overview(model: model, project: project) }
}
