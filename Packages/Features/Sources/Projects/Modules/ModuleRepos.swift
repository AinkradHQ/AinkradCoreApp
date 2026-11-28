import CoreUI
import SwiftUI

/// The Repos focused page (details v2). Contract stub: shows today's page until its lane builds the approved one.
struct ModuleRepos: View {
    let model: ProjectsModel
    let project: ProjectItem
    var body: some View { ReposPage(model: model, project: project) }
}
