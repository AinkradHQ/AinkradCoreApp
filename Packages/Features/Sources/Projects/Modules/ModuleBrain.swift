import CoreUI
import SwiftUI

/// The Brain focused page (details v2). Contract stub: shows today's page until its lane builds the approved one.
struct ModuleBrain: View {
    let model: ProjectsModel
    let project: ProjectItem
    var body: some View { BrainPage(model: model, project: project) }
}
