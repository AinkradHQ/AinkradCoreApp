import CoreUI
import Observation
import Shell
import SwiftUI

/// Settings, Apps, Brain: the Look and a way in.
struct BrainLookSection: View {
    @Environment(\.coreAccent) private var paneAccent
    let model: BrainModel
    @State private var ai: AISettings
    @State private var same: SameProjectList
    let part: SettingsPart
    init(model: BrainModel, part: SettingsPart = .all) {
        self.part = part
        self.model = model
        _ai = State(initialValue: AISettings(routes: { [weak model] in model?.service?.importRoutes }))
        _same = State(initialValue: SameProjectList(routes: { [weak model] in model?.service?.importRoutes }))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            if part.showsLook {
                AppLookSection(appName: "Brain", prefs: AppLookPrefs.shared("brain"))
            }
            if part.showsOptions {
                BrainLearningSection(settings: ai)
                GlassSection(
                    "The Brain", sub: "Rooms of memory, kept sealed apart.", symbol: "brain",
                    hue: GlassInk.accent(paneAccent), index: 1
                ) {
                    AppActionTile(
                        title: "Open", symbol: "arrow.up.forward.app", key: "", hue: GlassInk.accent(paneAccent),
                        prominent: true
                    ) {
                        model.host.shell.overlay = nil
                        model.show(.overview)
                    }
                } content: {
                    EmptyView()
                }
                BrainAISection(settings: ai)
                if model.remembersSameProject { SameProjectSection(list: same) }
            }
        }
        .foregroundStyle(GlassInk.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { if model.remembersSameProject { await same.reload() } }
    }
}
