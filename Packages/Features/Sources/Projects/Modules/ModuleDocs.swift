import CoreUI
import SwiftUI

/// The Docs focused page (details v2). Contract stub: shows today's page until its lane builds the approved one.
struct ModuleDocs: View {
    let model: ProjectsModel
    let project: ProjectItem
    var body: some View { DocsPage(model: model, project: project) }
}
