import CoreUI
import SwiftUI

/// The five About you pages (D-9). Everything is optional; what is picked becomes sentences in the Brain's Me space.
struct SetupYouPage: View {
    @Bindable var model: SetupTourModel
    let step: SetupTourModel.Step

    var body: some View {
        switch step {
        case .role: role
        case .stack: stack
        case .hours: SetupHoursPage(profile: $model.profile)
        case .style: style
        default: life
        }
    }

    private static let roleSymbols = ["terminal", "paintbrush", "doc.text", "magnifyingglass", "person.2", "ellipsis"]

    private var role: some View {
        SetupPage(
            meta: "About you · 1 of 5", title: "What do you do?",
            sub: "Pick everything that fits. This helps the AI talk about your work in your words."
        ) {
            // The first question of About you; it is also the name Home greets you with.
            CoreTextField(
                "What should we call you?", placeholder: "Sam", text: $model.profile.name, autofocus: true,
                onSubmit: {})
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.s3), count: 3), spacing: Space.s3) {
                ForEach(Array(SetupProfile.roles.enumerated()), id: \.offset) { i, r in
                    SetupOption(symbol: Self.roleSymbols[i], title: r, on: model.profile.roleSet.contains(r)) {
                        toggle(&model.profile.roleSet, r)
                    }
                }
            }
            SetupGroup(title: "What kind of work?") {
                SetupChips(options: SetupProfile.workKinds, chosen: $model.profile.workSet)
            }
        }
    }

    private var stack: some View {
        SetupPage(meta: "About you · 2 of 5", title: "What do you work with?", sub: "Tap anything you use. Skip what you do not.") {
            SetupGroup(title: "Languages") { SetupChips(options: SetupProfile.languages, chosen: $model.profile.languageSet) }
            SetupGroup(title: "Tools") { SetupChips(options: SetupProfile.tools, chosen: $model.profile.toolSet) }
            SetupGroup(title: "Where you run things") {
                SetupChips(options: SetupProfile.hosting, chosen: $model.profile.hostingSet)
            }
        }
    }

    private static let toneSymbols = ["bolt", "sparkles", "doc.text"]

    private var style: some View {
        SetupPage(meta: "About you · 4 of 5", title: "How should the AI talk to you?", sub: "") {
            HStack(alignment: .top, spacing: Space.s3) {
                ForEach(Array(SetupProfile.tones.enumerated()), id: \.offset) { i, t in
                    SetupOption(symbol: Self.toneSymbols[i], title: t.0, sub: t.1, on: model.profile.tone == i) {
                        model.profile.tone = model.profile.tone == i ? nil : i
                    }
                }
            }
            SetupGroup(title: "What can it take off your plate?") {
                SetupChips(options: SetupProfile.goals, chosen: $model.profile.goalSet)
            }
        }
    }

    private var life: some View {
        SetupPage(meta: "About you · 5 of 5", title: "A little more about you", sub: "Last page. Everything here is optional.") {
            SetupGroup(title: "Languages you speak") { SetupChips(options: SetupProfile.spoken, chosen: $model.profile.spokenSet) }
            SetupGroup(title: "What you focus on") { SetupChips(options: SetupProfile.focus, chosen: $model.profile.focusSet) }
            SetupGroup(title: "Routines") { SetupChips(options: SetupProfile.routines, chosen: $model.profile.routineSet) }
        }
    }

    private func toggle(_ set: inout Set<String>, _ v: String) {
        if set.contains(v) { set.remove(v) } else { set.insert(v) }
    }
}
