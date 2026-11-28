import CoreUI
import SwiftUI

/// The Services focused page (details v2). Contract stub: shows today's page until its lane builds the approved one.
struct ModuleServices: View {
    let model: ProjectsModel
    let project: ProjectItem
    var body: some View { RunsPage(model: model, project: project) }
}
