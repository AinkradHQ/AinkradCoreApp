import CoreUI
import SwiftUI

/// "What is it?": four big choices, the suggested one marked, and one plain line on why it is suggested.
struct WizardKindStep: View {
    @Binding var kind: ProjectKind
    let suggestion: KindSuggestion
    /// The person chose; the suggestion stops following the repos and its line goes away.
    @Binding var chosenByPerson: Bool
    @Environment(\.corePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            DialogHead(
                title: "What is it?",
                line: "This decides which pages and buttons the project shows. You can change it later.")
            Grid(horizontalSpacing: Space.s2, verticalSpacing: Space.s2) {
                ForEach(Array(stride(from: 0, to: ProjectKind.allCases.count, by: 2)), id: \.self) { i in
                    GridRow {
                        ForEach(ProjectKind.allCases[i..<min(i + 2, ProjectKind.allCases.count)]) { k in tile(k) }
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            if !chosenByPerson {
                Text(suggestion.why).foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
        .animation(Motion.out(Motion.ui), value: chosenByPerson)
    }

    private func tile(_ k: ProjectKind) -> some View {
        WizardChoiceTile(
            symbol: k.symbol, title: k == suggestion.kind ? "\(k.short) · Suggested" : k.short, line: k.line,
            selected: kind == k
        ) {
            kind = k
            chosenByPerson = true
        }
        .accessibilityIdentifier("project-new-kind-\(k.rawValue)")
    }
}

/// "Where should it run?" (an app: "build"): the runner, and for a web project the public link.
struct WizardRunsStep: View {
    let model: ProjectsModel
    let kind: ProjectKind
    @Binding var runner: WizardRunner
    @Binding var publicLink: Bool
    let host: String
    @Environment(\.corePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            DialogHead(
                title: kind == .app ? "Where should it build?" : "Where should it run?",
                line: kind == .app
                    ? "The machine that builds it. Apple apps need a Mac. You can change this later."
                    : "You can change this later.")
            HStack(spacing: Space.s2) {
                ForEach(WizardRunner.allCases, id: \.self) { r in
                    WizardChoiceTile(
                        symbol: r.symbol, title: r == .auto ? "\(r.title) · Best" : r.title,
                        line: r.line(model.runners), selected: runner == r
                    ) { runner = r }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            if !model.runnerSupported {
                Text("This Core keeps one place for now. The choice is remembered when it can.")
                    .foregroundStyle(palette.text2)
            }
            if kind.hasPublicLink {
                HStack(alignment: .top, spacing: Space.s3) {
                    VStack(alignment: .leading, spacing: Space.s1) {
                        Text("Public link").coreFont(size: MacTextSize.body, weight: .semibold)
                        Text("Anyone with the link can see the project page, not your code.")
                            .foregroundStyle(palette.text2)
                        if publicLink {
                            Text(host).font(.system(size: MacTextSize.body, design: .monospaced))
                                .foregroundStyle(palette.text2)
                        }
                    }
                    Spacer()
                    CoreSwitch("Public link", isOn: $publicLink)
                }
                .padding(Space.s3).coreCard(GlassInk.well, radius: Radius.cardMac)
            }
        }
    }
}
