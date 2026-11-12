import CoreUI
import SwiftUI

extension AccountDialogs {
    /// New (editing nil) or edit: the advanced sheet. The quick New chain makes one at once with defaults.
    static func openChain(_ m: AccountsModel, editing: ChainItem?, reason: String? = nil) {
        m.note("chain", reason)
        present(m, "chain") { close in ChainDialog(model: m, editing: editing, close: close) }
    }
    static func openDeleteChain(_ m: AccountsModel, _ c: ChainItem) {
        present(m, "chain-delete") { close in DeleteChainDialog(model: m, chain: c, close: close) }
    }
}

/// What a chain may hold, checked before the Core is asked. The Core checks the rest (a subscription pool at most once).
enum ChainRules {
    static func issue(name: String, entries: [ChainEntryDraft]) -> String? {
        if !PoolName.isValid(name.trimmingCharacters(in: .whitespaces)) { return PoolName.rule }
        if !(1...ChainItem.maxEntries).contains(entries.count) { return "A chain has 1 to 4 pools." }
        if Set(entries.map(\.pool)).count != entries.count {
            return "Each pool can be in a chain once. Pick a different pool."
        }
        return nil
    }
}

private struct ChainDialog: View {
    let model: AccountsModel
    let editing: ChainItem?
    let close: () -> Void
    @State private var name: String
    @State private var entries: [ChainEntryDraft]
    @State private var busy = false
    @State private var fixing = false

    init(model: AccountsModel, editing: ChainItem?, close: @escaping () -> Void) {
        self.model = model
        self.editing = editing
        self.close = close
        _name = State(initialValue: editing?.name ?? model.nextChainName())
        _entries = State(
            initialValue: editing?.entries.map { ChainEntryDraft(pool: $0.pool, model: $0.model) }
                ?? (model.pools.first.map { [ChainEntryDraft(pool: $0.id, model: nil)] } ?? []))
    }

    private var issue: String? { ChainRules.issue(name: name, entries: entries) }

    var body: some View {
        let error = model.writeError["chain"]
        // A rule of the Core ("a subscription pool at most once"): the pools have to change, so that is the main action and
        // "Try again" (the same input) is the quiet one.
        let rule = error != nil && model.writeRule.contains("chain")
        CoreDialogPanel(editing == nil ? "New chain" : "Edit \(editing?.name ?? "chain")", width: Space.s8 * 17) {
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.s3) {
                        CoreTextField("Name", placeholder: "work", text: $name, autofocus: editing == nil)
                        CoreFieldLabel("Pools, in the order they're tried").id("chain-pools")
                        ForEach(entries.indices, id: \.self) { i in row(i) }
                        AccLink(title: "Add a pool", symbol: "plus") {
                            if let p = model.pools.first(where: { p in !entries.contains { $0.pool == p.id } }) {
                                entries.append(ChainEntryDraft(pool: p.id, model: nil))
                            }
                        }
                        .disabled(entries.count >= ChainItem.maxEntries || entries.count >= model.pools.count)
                        Text(
                            "A session tries the first pool that has an account to give. Running sessions keep the chain they started with."
                        )
                        .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxHeight: Space.s8 * 14)
                .onChange(of: fixing) { scroll.scrollTo("chain-pools", anchor: .top) }
            }
            if let issue, !name.isEmpty { AccIssue(text: issue) }
            if let error {
                AccIssue(
                    text: rule
                        ? "\(error) Change the pools, or cancel to leave the chain as it was."
                        : "\(error) Try again, or cancel to leave the chain as it was.")
            }
            AccNotice(notice: model.host.elevationNotice)
            if rule {
                CoreDialogFooter(
                    cancel: CoreAction("Cancel", key: .cancel, run: close),
                    primary: CoreAction("Change the pools", key: .primary) {
                        model.note("chain", nil)
                        fixing.toggle()
                    },
                    alternate: CoreAction("Try again", key: .command) { go() }, busy: busy, enabled: issue == nil)
            } else {
                AccDialogButtons(
                    confirm: error == nil ? (editing == nil ? "Create chain" : "Save") : "Try again", busy: busy,
                    enabled: issue == nil, cancel: close
                ) { go() }
            }
        }
        .accessibilityIdentifier("chain")
    }

    /// Bindings that look the row up each time: a row removed a moment ago must not be read.
    private func poolBinding(_ i: Int) -> Binding<Int64> {
        Binding(
            get: { entries.indices.contains(i) ? entries[i].pool : 0 },
            set: {
                guard entries.indices.contains(i) else { return }
                entries[i].pool = $0
                entries[i].model = nil
            })
    }

    private func modelBinding(_ i: Int) -> Binding<String> {
        Binding(
            get: { entries.indices.contains(i) ? entries[i].model ?? "" : "" },
            set: { if entries.indices.contains(i) { entries[i].model = $0.isEmpty ? nil : $0 } })
    }

    private func row(_ i: Int) -> some View {
        guard entries.indices.contains(i) else { return AnyView(EmptyView()) }
        return AnyView(rowBody(i))
    }

    private func rowBody(_ i: Int) -> some View {
        let pool = model.pool(entries[i].pool)
        let models = model.provider(pool?.provider ?? "")?.models ?? []
        return HStack(alignment: .bottom, spacing: Space.s2) {
            Text("\(i + 1)").coreFont(size: MacTextSize.body, weight: .bold, design: .rounded)
                .foregroundStyle(GlassInk.secondary).frame(width: 20).padding(.bottom, Space.s2)
            CoreSelect(
                "Pool", selection: poolBinding(i),
                options: model.pools.map {
                    CoreSelectOption($0.id, "\(model.providerName($0.provider)) · \($0.name)")
                })
            if models.isEmpty {
                CoreTextField(
                    "Model", placeholder: "the provider's default model",
                    text: modelBinding(i), mono: true)
            } else {
                CoreSelect(
                    "Model",
                    selection: modelBinding(i),
                    options: [CoreSelectOption("", "Provider's default model")]
                        + models.map { CoreSelectOption($0.id, $0.id) })
            }
            AccLink(title: "Up", symbol: "arrow.up", help: "Try this pool earlier") { entries.swapAt(i, i - 1) }
                .disabled(i == 0)
            AccLink(title: "Remove", symbol: "xmark", danger: true, help: "Take this pool out") {
                entries.remove(at: i)
            }
            .disabled(entries.count == 1)
        }
    }

    private func go() {
        guard issue == nil else { return }
        busy = true
        Task {
            let ok =
                if let editing { await model.replace(editing, name: name, entries: entries) } else {
                    await model.createChain(name: name, entries: entries)
                }
            busy = false
            if ok { close() }
        }
    }
}

private struct DeleteChainDialog: View {
    let model: AccountsModel
    let chain: ChainItem
    let close: () -> Void
    @State private var busy = false
    var body: some View {
        let n = model.agents(of: chain).count
        let error = model.writeError["delete-chain-\(chain.id)"]
        CoreDialogPanel("Delete \(chain.name)?", width: Space.s8 * 14) {
            VStack(alignment: .leading, spacing: Space.s3) {
                Text(
                    "The chain goes\(n == 0 ? "" : ", and so do its \(n) AI session binding\(n == 1 ? "" : "s")"). Running sessions keep going. The pools and accounts stay.\(chain.isDefault ? " It is the default, so sessions with no chain run plain until you pick another default." : "")"
                )
                .fixedSize(horizontal: false, vertical: true)
                if let error { AccIssue(text: "\(error) Try again, or cancel and leave the chain as it is.") }
                AccNotice(notice: model.host.elevationNotice)
                AccDialogButtons(
                    confirm: error == nil ? "Delete chain" : "Try again", danger: true, busy: busy, cancel: close
                ) {
                    busy = true
                    Task {
                        let ok = await model.delete(chain)
                        busy = false
                        if ok { close() }
                    }
                }
            }
        }
        .accessibilityIdentifier("chain-delete")
    }
}
