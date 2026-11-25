import AppKit
import CoreUI
import SwiftUI

// MARK: 4. which ones

extension ConnAddView {
    var chooseStep: some View {
        let noun = kind?.resource ?? "places"
        let saving = model.busy?.hasPrefix("access-") == true
        return VStack(spacing: Space.s3) {
            head("Which \(noun)?", "Your assistant only sees what you tick.")
            toolbar(noun)
            pickList(noun)
            if a.kind == "github" { missingRepos }
            if a.kind == "jira" { otherSites }
            if let e = model.addError { AccIssue(text: e) }
            if let c = a.connection, model.gated.contains("access-\(c)") {
                TurnOnConnections(model: model) { await model.finishAdd() }
            }
            footer(
                primary: (a.finishTitle(noun: noun, saving: saving), { Task { await model.finishAdd() } }),
                enabled: a.canFinish && !saving, busy: saving)
        }
    }

    private var rows: [ConnPick] {
        if case .ready(let p) = model.picks { return a.visible(p.items) }
        return []
    }

    /// Search, how many are ticked, and Select All, on one line at the buttons' height.
    private func toolbar(_ noun: String) -> some View {
        let query = Binding(get: { a.query }, set: { model.add?.query = $0 })
        let rows = rows
        let all = a.allPicked(rows)
        return HStack(spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Image(systemName: "magnifyingglass").coreFont(size: MacTextSize.body, weight: .medium)
                    .foregroundStyle(GlassInk.secondary).accessibilityHidden(true)
                TextField("", text: query, prompt: Text("Search \(noun)").foregroundStyle(GlassInk.secondary))
                    .textFieldStyle(.plain).autocorrectionDisabled()
                    .accessibilityLabel("Search \(noun)")
                if !a.query.isEmpty {
                    CoreIconButton(symbol: "xmark", label: "Clear the search") { model.add?.query = "" }
                }
            }
            .padding(.horizontal, Space.s3).frame(height: MacSize.controlMd)
            .coreFieldSurface()
            Text(a.countLine).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                .monospacedDigit().fixedSize()
            Button(all ? "Clear All" : "Select All") {
                if all { model.add?.clearAll(rows) } else { model.add?.selectAll(rows) }
            }
            .buttonStyle(CoreButtonStyle(.secondary, size: .medium)).disabled(rows.isEmpty)
        }
    }

    /// GitHub only lists repositories where the Ainkrad GitHub App is installed, even ones you can open. Installing it on
    /// another account or organization brings them in (the list reloads when you come back); a token sees them all.
    private var missingRepos: some View {
        HStack(spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Missing a repository?").coreFont(size: MacTextSize.meta, weight: .semibold)
                Text("Only where Ainkrad is installed on GitHub.").coreFont(size: MacTextSize.meta)
                    .foregroundStyle(GlassInk.secondary)
            }
            Spacer(minLength: 0)
            HStack(spacing: Space.s2) {
                AccLink(title: "Add an organization", symbol: "plus") {
                    installing = true
                    NSWorkspace.shared.open(URL(string: "https://github.com/apps/ainkradhq/installations/new")!)
                }
                AccLink(title: "Use a token", symbol: "key") { token = true }
            }
            .fixedSize()
        }
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
        .background(GlassInk.well, in: coreShape(Radius.control))
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            guard installing else { return }
            installing = false
            Task { await model.loadPicks() }
        }
    }

    /// Atlassian ties a sign-in to one site: projects shared with you on another company's site need a connection of
    /// their own. "Connect another site" saves these choices first, then signs in again (pick the other site there).
    private var otherSites: some View {
        HStack(spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Missing a project?").coreFont(size: MacTextSize.meta, weight: .semibold)
                Text("Projects on another Atlassian site need their own connection.").coreFont(size: MacTextSize.meta)
                    .foregroundStyle(GlassInk.secondary)
            }
            Spacer(minLength: 0)
            HStack(spacing: Space.s2) {
                AccLink(
                    title: "Connect another site", symbol: "plus",
                    help: "Saves these projects, then signs in again. Pick the other site on Atlassian’s page."
                ) {
                    Task {
                        await model.finishAdd()
                        if model.addError == nil { model.pick(service: "jira") }
                    }
                }
                .disabled(!a.canFinish)
                AccLink(title: "Use a token", symbol: "key") { token = true }
            }
            .fixedSize()
        }
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
        .background(GlassInk.well, in: coreShape(Radius.control))
    }

    @ViewBuilder private func pickList(_ noun: String) -> some View {
        switch model.picks {
        case .idle, .loading:
            VStack(spacing: 0) {
                ForEach(0..<4, id: \.self) { _ in
                    CoreSkeleton(coreShape(Radius.control)).frame(height: Space.s6).padding(Space.s2)
                }
            }
            .background(GlassInk.well, in: coreShape(Radius.control))
            .accessibilityLabel("Loading \(noun)")
        case .failed(let why):
            CoreNotice(symbol: "exclamationmark.triangle", title: "Couldn't read your \(noun)", text: why, tone: .fail)
            {
                Button("Try again") { Task { await model.loadPicks() } }.buttonStyle(CoreButtonStyle(.secondary))
            }
        case .ready(let p):
            let rows = a.visible(p.items)
            if rows.isEmpty {
                Text(p.items.isEmpty ? "There is nothing to choose yet." : "No \(noun) match.")
                    .foregroundStyle(GlassInk.secondary).frame(maxWidth: .infinity).padding(.vertical, Space.s6)
                    .background(GlassInk.well, in: coreShape(Radius.control))
            } else {
                // One well holding compact rows, not a card per row; the bottom edge fades so a cut row reads as "more".
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { r in ConnPickRow(pick: r, on: a.picked.contains(r.id)) { model.add?.toggle(pick: r.id) } }
                    }
                    .padding(Space.s1)
                }
                .scrollIndicators(.automatic).frame(maxHeight: 264)
                .mask {
                    let fade = rows.count > 6
                    LinearGradient(
                        stops: [.init(color: .black, location: 0.9), .init(color: .black.opacity(fade ? 0 : 1), location: 1)],
                        startPoint: .top, endPoint: .bottom)
                }
                .background(GlassInk.well, in: coreShape(Radius.control))
                if p.truncated {
                    Text("There are more. Type in the search to narrow the list.").coreFont(size: MacTextSize.meta)
                        .foregroundStyle(GlassInk.secondary)
                }
            }
        }
    }
}

/// One repository (or project, channel): the name, then the owner and when it changed, quiet. Hover lightens the row.
struct ConnPickRow: View {
    let pick: ConnPick
    let on: Bool
    let toggle: () -> Void
    @State private var hover = false

    var body: some View {
        let parts = pick.name.split(separator: "/", maxSplits: 1).map(String.init)
        let title = parts.count == 2 ? parts[1] : pick.name
        let detail = ([parts.count == 2 ? parts[0] : nil, ConnAccess.line(pick)].compactMap { $0 }).joined(separator: " · ")
        CoreCheckbox(title, detail: detail.isEmpty ? nil : detail,
                     isOn: Binding(get: { on }, set: { _ in toggle() }), spoken: pick.name)
            .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hover ? GlassInk.wellHover : .clear, in: coreShape(Radius.control - 2))
            .onHover { hover = $0 }
            .animation(Motion.out(Motion.hover), value: hover)
    }
}
