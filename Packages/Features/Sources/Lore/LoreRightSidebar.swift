// LoreRightSidebar — the inspector of the open note (E10-1): a few quiet facts, the outline as a small map of its
// headings, the notes that link here as cards, and the latest versions. A section with nothing to show is left out;
// a section title folds its section away (kept per user).
import CoreKit
import CoreUI
import SwiftUI

/// ⌘3 puts the cursor here: ↑ ↓ walk the headings, backlinks and versions, Return goes to the heading, opens the
/// backlink or shows the version; Esc goes back to the note.
struct LoreRightSidebar: View {
    let model: LoreModel
    var focus: FocusState<Bool>.Binding
    @State private var picked: Int?
    @State private var cursor: String?
    @AppStorage("lore.inspector.folded") private var foldedList = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s1) {
                    // Nothing about a note until one is open (not connected, loading, failed).
                    if model.load == .ready { facts }
                    if showsOutline {
                        section("Outline", count: model.outline.count)
                        if !folded("Outline") { outline }
                    }
                    if model.load == .ready, !model.backlinks.isEmpty {
                        section("Linked from", count: model.backlinks.count)
                        if !folded("Linked from") { backlinks }
                    }
                    if showsVersions {
                        section("Versions", count: nil)
                        if !folded("Versions") { versions }
                    }
                }
                .padding(.bottom, Space.s4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.never)
            .onChange(of: cursor) { if let cursor { proxy.scrollTo(cursor) } }
        }
        .focusable()
        .focused(focus)
        .focusEffectDisabled()
        .loreListKeys(ids, cursor: $cursor, run: run) {
            focus.wrappedValue = false
            // After SwiftUI has let go of its focus, or it takes the first responder back from the page.
            Task { @MainActor in model.page.focus() }
        }
        .onChange(of: focus.wrappedValue) { cursor = focus.wrappedValue ? ids.first : nil }
        .animation(reduceMotion ? nil : Motion.out(Motion.ui), value: foldedList)
        .accessibilityIdentifier("lore-right")
    }

    /// One heading is the title the page already shows: an outline needs two.
    private var showsOutline: Bool { model.load == .ready && model.outline.count > 1 }
    /// Only the current version is no history yet.
    private var showsVersions: Bool { model.load == .ready && model.sideVersions.count > 1 }
    private var shownVersions: [LoreVersion] { Array(model.sideVersions.prefix(6)) }

    private var ids: [String] {
        var out: [String] = []
        if showsOutline, !folded("Outline") { out += model.outline.map { "h:\($0.id)" } }
        if !folded("Linked from") { out += model.backlinks.map { "b:\($0.note)" } }
        if showsVersions, !folded("Versions") { out += shownVersions.map { "v:\($0.id)" } }
        return out
    }

    private func go(_ h: LoreHeading) {
        picked = h.id
        model.reveal(h)
    }

    private func run(_ id: String) {
        let value = String(id.dropFirst(2))
        switch id.prefix(2) {
        case "h:": if let h = model.outline.first(where: { "\($0.id)" == value }) { go(h) }
        case "b:": Task { await model.openNote(value) }
        default: model.showVersions(selecting: value)
        }
    }

    // MARK: folding

    private func folded(_ name: String) -> Bool { foldedList.split(separator: ",").contains { $0 == name } }

    private func fold(_ name: String) {
        var set = foldedList.split(separator: ",").map(String.init)
        if let i = set.firstIndex(of: name) { set.remove(at: i) } else { set.append(name) }
        foldedList = set.joined(separator: ",")
    }

    private func section(_ name: String, count: Int?) -> some View {
        LoreFoldTitle(name: name, count: count, folded: folded(name)) { fold(name) }
            .padding(.top, Space.s4)
    }

    // MARK: parts

    /// Words and reading time, then the note's tags as chips (the header shows where it lives). No labels, no "None".
    private var facts: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            if model.wordCount > 0 {
                let words = model.wordCount == 1 ? "1 word" : "\(model.wordCount) words"
                Text("\(words) · \(LoreWeek.readingMinutes(model.wordCount)) min read")
                    .coreFont(size: MacTextSize.meta + 1).foregroundStyle(GlassInk.secondary)
                    .monospacedDigit()
                    .accessibilityIdentifier("lore-words")
            }
            if !model.noteTags.isEmpty {
                FlowRow(spacing: Space.s2) {
                    ForEach(model.noteTags, id: \.self) { t in
                        LoreTagChip(tag: t, on: model.sideFilter == .tag(t), cursor: false) {
                            model.showLeft = true
                            model.setFilter(.tag(t))
                        }
                    }
                }
            }
            if let doc = model.openDoc {
                Label(doc.path, systemImage: "doc").coreFont(size: MacTextSize.meta)
                    .foregroundStyle(GlassInk.secondary).lineLimit(1).truncationMode(.middle).help(doc.path)
            }
        }
        .padding(.horizontal, Space.s3).padding(.top, Space.s2)
    }

    /// The headings as a small map: deeper headings step in and get lighter.
    private var outline: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(model.outline) { h in
                LoreOutlineRow(heading: h, picked: picked == h.id, cursor: cursor == "h:\(h.id)") { go(h) }
                    .id("h:\(h.id)")
            }
        }
        .transition(.opacity)
    }

    private var backlinks: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            ForEach(model.backlinks) { b in
                LoreBacklinkCard(backlink: b, cursor: cursor == "b:\(b.note)") {
                    Task { await model.openNote(b.note) }
                }
                .id("b:\(b.note)")
            }
        }
        .transition(.opacity)
    }

    private var versions: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(shownVersions.enumerated()), id: \.element.id) { i, v in
                VersionRow(model: model, version: v, current: i == 0, cursor: cursor == "v:\(v.id)")
                    .id("v:\(v.id)")
            }
            Button("All versions…") { model.showVersions() }
                .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                .environment(\.coreKeycap, LoreKeys.versions.label)
                .padding(.leading, Space.s3).padding(.top, Space.s2)
                .help(LoreKeys.versions.help)
        }
        .transition(.opacity)
    }
}

/// A section's title: a button that folds the section, with a small count. The chevron turns; Reduce Motion: it
/// just changes.
private struct LoreFoldTitle: View {
    let name: String
    let count: Int?
    let folded: Bool
    let toggle: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: Space.s1) {
                Text(name).coreFont(size: MacTextSize.meta + 1, weight: .semibold)
                if let count {
                    Text("\(count)").coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                        .monospacedDigit()
                }
                Spacer(minLength: Space.s2)
                Image(systemName: "chevron.down").coreFont(size: MacTextSize.meta, weight: .semibold)
                    .rotationEffect(.degrees(folded ? -90 : 0))
                    .opacity(hover || folded ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(GlassInk.secondary)
            .padding(.horizontal, Space.s3).frame(minHeight: MacSize.controlSm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(Motion.out(Motion.hover), value: hover)
        .help(folded ? "Show \(name.lowercased())" : "Hide \(name.lowercased())")
        .accessibilityAddTraits(.isHeader)
        .accessibilityValue(folded ? "Hidden" : "Shown")
    }
}

private struct LoreOutlineRow: View {
    let heading: LoreHeading
    let picked: Bool
    let cursor: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Text(heading.title)
                .coreFont(size: heading.level == 1 ? MacTextSize.body : MacTextSize.meta + 1,
                    weight: heading.level == 1 ? .semibold : .regular)
                .foregroundStyle(heading.level == 3 ? GlassInk.secondary : GlassInk.primary)
                .lineLimit(1).truncationMode(.tail)
                .padding(.leading, Space.s3 + CGFloat(heading.level - 1) * Space.s3).padding(.trailing, Space.s3)
                .frame(maxWidth: .infinity, minHeight: MacSize.controlSm + Space.s1, alignment: .leading)
                .background(
                    cursor ? GlassInk.lift(0.16) : picked || hover ? GlassInk.wellHover : .clear,
                    in: coreShape(Radius.control)
                )
                .contentShape(coreShape(Radius.control))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(Motion.out(Motion.hover), value: hover)
        .help("Go to “\(heading.title)”")
        .accessibilityAddTraits(picked || cursor ? .isSelected : [])
    }
}

/// A note that links here, as a small card: its title and the line the link sits in.
private struct LoreBacklinkCard: View {
    let backlink: LoreBacklink
    let cursor: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        let title = backlink.title.isEmpty ? "Untitled note" : backlink.title
        Button(action: action) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text(title).coreFont(size: MacTextSize.body, weight: .medium).lineLimit(1)
                if !backlink.context.isEmpty {
                    Text(backlink.context).coreFont(size: MacTextSize.meta + 1).foregroundStyle(GlassInk.secondary)
                        .lineLimit(2)
                }
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .coreWell(radius: Radius.cardMac, active: hover || cursor)
            // The keyboard's card (⌘3, ↑ ↓) is lit with the rows' cursor fill, so it reads on a light Look too.
            .overlay {
                coreShape(Radius.cardMac).fill(GlassInk.wellHover).opacity(cursor ? 1 : 0).allowsHitTesting(false)
            }
            .contentShape(coreShape(Radius.cardMac))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(Motion.out(Motion.hover), value: hover)
        .help("Open \(title)")
    }
}

/// One version: when and who, a small mark (filled for the current one), Restore on hover or under the cursor.
private struct VersionRow: View {
    let model: LoreModel
    let version: LoreVersion
    let current: Bool
    var cursor = false
    @State private var hover = false
    @Environment(\.corePalette) private var palette

    var body: some View {
        HStack(spacing: Space.s2) {
            RoundedRectangle(cornerRadius: 2).fill(current ? palette.primary : GlassInk.track)
                .frame(width: Space.s2 - 2, height: Space.s2 - 2).accessibilityHidden(true)
            Text(current ? "Now" : LoreVersionWords.detail(version)).coreFont(size: MacTextSize.meta + 1)
                .foregroundStyle(current ? GlassInk.primary : GlassInk.secondary)
                .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: Space.s1)
            if !current, hover || cursor {
                Button("Restore") { Task { await model.restore(version.id) } }
                    .buttonStyle(CoreButtonStyle(.secondary, size: .small)).help("Bring back this version")
            }
        }
        .padding(.horizontal, Space.s3).frame(minHeight: MacSize.controlMd)
        .background(
            cursor ? GlassInk.lift(0.16) : hover ? GlassInk.wellHover : .clear, in: coreShape(Radius.control)
        )
        .contentShape(coreShape(Radius.control))
        .onTapGesture { model.showVersions(selecting: version.id) }
        .onHover { hover = $0 }
        .animation(Motion.out(Motion.hover), value: hover)
        .help(LoreVersionWords.title(version))
    }
}
