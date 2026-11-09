import CoreUI
import SwiftUI

/// A provider definition of your own (OpenRouter or any API that speaks one of the three wires). It holds keys through the
/// gateway only, so it always has a key prefix; Core checks the rest again and says why when it refuses.
struct ProviderDraft: Equatable, Sendable {
    struct Model: Equatable, Sendable, Identifiable {
        var id: String
        var input: Int64
        var output: Int64
    }
    var id: String
    var name: String
    var harness: String
    var baseURL: String
    var keyPrefix: String
    var testPath: String?
    var models: [Model]

    var authVar: String { ProviderRules.wires.first { $0.harness == harness }?.authVar ?? "" }
    var usageParser: String { ProviderRules.wires.first { $0.harness == harness }?.parser ?? "none" }
}

/// Core's rules for a definition (`store/providers.rs`, `provider_url.rs`, `provider_rules.rs`), in words.
enum ProviderRules {
    static let wires: [(harness: String, title: String, sub: String, authVar: String, parser: String)] = [
        ("claude", "Anthropic Messages", "For Claude Code", "ANTHROPIC_API_KEY", "anthropic"),
        ("codex", "OpenAI Responses", "For Codex", "OPENAI_API_KEY", "openai"),
        ("agy", "Gemini", "For agy", "GEMINI_API_KEY", "google"),
    ]

    /// `OpenRouter EU` → `openrouter-eu`: [a-z][a-z0-9-]{0,31}.
    static func id(from name: String) -> String {
        var s = name.lowercased().map { $0.isLetter && $0.isASCII || $0.isNumber ? $0 : "-" }.reduce("") {
            $0 + String($1)
        }
        while s.contains("--") { s = s.replacingOccurrences(of: "--", with: "-") }
        s = String(s.trimmingCharacters(in: CharacterSet(charactersIn: "-")).prefix(32))
        while let f = s.first, !f.isLetter { s.removeFirst() }
        return s
    }

    static func nameIssue(_ n: String) -> String? {
        let t = n.trimmingCharacters(in: .whitespaces)
        if t.isEmpty || t.count > 64 { return "A name is 1 to 64 characters." }
        return id(from: t).isEmpty ? "Start the name with a letter." : nil
    }

    /// https, a public DNS name, port 443 at most, no credentials, query, IP address or punycode.
    static func urlIssue(_ u: String) -> String? {
        guard let rest = u.hasPrefix("https://") ? String(u.dropFirst(8)) : nil else {
            return "The address starts with https://."
        }
        if rest.contains(where: { "@?#\\ ".contains($0) }) { return "Only the address: no name, password, ? or #." }
        let authority = rest.split(separator: "/", maxSplits: 1).first.map(String.init) ?? ""
        let parts = authority.split(separator: ":", maxSplits: 1)
        if parts.count == 2, parts[1] != "443" { return "No port: Core only talks to the standard one." }
        let host = String(parts.first ?? "")
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        if labels.count < 2 || host.hasSuffix(".") { return "Use the provider's domain name, like openrouter.ai." }
        if labels.allSatisfy({ $0.allSatisfy(\.isNumber) }) { return "Use a domain name, not an IP address." }
        if labels.contains(where: { $0.hasPrefix("xn--") }) { return "Use the plain domain name, not punycode." }
        let ok = labels.allSatisfy { l in
            (1...63).contains(l.count) && !l.hasPrefix("-") && !l.hasSuffix("-")
                && l.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "-") }
        }
        return ok ? nil : "Lowercase letters, digits and dashes only."
    }

    static func prefixIssue(_ p: String) -> String? {
        (6...16).contains(p.count) && !p.contains(" ")
            ? nil : "The start every key of this provider shares, 6 to 16 characters, like sk-or-v1-."
    }

    static func testPathIssue(_ p: String) -> String? {
        if p.isEmpty { return nil }
        let ok =
            p.hasPrefix("/") && (2...100).contains(p.count)
            && p.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "._~/-".contains($0)) }
            && p.dropFirst().split(separator: "/", omittingEmptySubsequences: false).allSatisfy {
                !$0.isEmpty && $0 != "." && $0 != ".."
            }
        return ok ? nil : "A path under the address, like /key."
    }

    static func modelIssue(_ m: String) -> String? {
        if let i = CostWords.modelIssue(m) { return i }
        let ok = m.count <= 80 && m.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "._:/-".contains($0)) }
        return ok ? nil : "Letters, digits and . _ : / - only."
    }
}

extension AccountsModel {
    func saveProvider(_ p: ProviderDraft, replacing: Bool) async -> Bool {
        await write(
            "provider", reason: replacing ? "Change the provider \(p.name)." : "Add the provider \(p.name).",
            done: replacing ? "\(p.name) saved" : "\(p.name) added", keepsEdit: true
        ) { try await $0.saveProvider(p, replacing: replacing) }
    }

    func deleteProvider(_ p: ProviderItem) async -> Bool {
        await write("provider-\(p.id)", reason: "Remove the provider \(p.name).", done: "\(p.name) removed") {
            try await $0.deleteProvider(p.id)
        }
    }
}

/// Add or change your own provider. Once accounts use it, how it speaks and its key prefix are fixed.
struct ProviderDialog: View {
    let model: AccountsModel
    let editing: ProviderItem?
    let close: () -> Void
    @State private var name: String
    @State private var harness: String
    @State private var url: String
    @State private var prefix: String
    @State private var testPath: String
    @State private var models: [ProviderDraft.Model]
    @State private var newModel = ""
    @State private var busy = false

    init(model: AccountsModel, editing: ProviderItem?, close: @escaping () -> Void) {
        self.model = model
        self.editing = editing
        self.close = close
        _name = State(initialValue: editing?.name ?? "")
        _harness = State(initialValue: editing?.harness ?? "claude")
        _url = State(initialValue: editing?.baseURL ?? "https://")
        _prefix = State(initialValue: editing?.keyPrefix ?? "")
        _testPath = State(initialValue: editing?.testPath ?? "")
        _models = State(
            initialValue: editing?.models.map { .init(id: $0.id, input: $0.inputMicro, output: $0.outputMicro) } ?? [])
    }

    /// Accounts already use it: its wire and key prefix stay as they are.
    private var frozen: Bool { editing.map { p in model.accounts.contains { $0.provider == p.id } } ?? false }
    private var id: String { editing?.id ?? ProviderRules.id(from: name) }
    private var issue: String? {
        ProviderRules.nameIssue(name) ?? ProviderRules.urlIssue(url) ?? ProviderRules.prefixIssue(prefix)
            ?? ProviderRules.testPathIssue(testPath)
    }

    var body: some View {
        CoreDialogPanel(editing.map { "Provider: \($0.name)" } ?? "Add a provider", width: Space.s8 * 22) {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(alignment: .top, spacing: Space.s3) {
                    CoreTextField(
                        "Name", placeholder: "OpenRouter", text: $name,
                        error: name.isEmpty ? nil : ProviderRules.nameIssue(name), autofocus: editing == nil)
                    CoreTextField(
                        "Address", placeholder: "https://openrouter.ai/api", text: $url,
                        error: url.count <= 8 ? nil : ProviderRules.urlIssue(url), mono: true)
                }
                CoreFieldLabel("How it speaks")
                HStack(spacing: Space.s2) {
                    ForEach(ProviderRules.wires, id: \.harness) { w in
                        AccPick(
                            title: w.title, sub: w.sub, symbol: "point.3.connected.trianglepath.dotted",
                            hue: GlassInk.blue, on: harness == w.harness, enabled: !frozen || harness == w.harness
                        ) { harness = w.harness }
                    }
                }
                HStack(alignment: .top, spacing: Space.s3) {
                    CoreTextField(
                        "Key prefix", placeholder: "sk-or-v1-", text: $prefix,
                        error: prefix.isEmpty ? nil : ProviderRules.prefixIssue(prefix), mono: true
                    )
                    .disabled(frozen)
                    CoreTextField(
                        "Key test path (optional)", placeholder: "/key", text: $testPath,
                        error: ProviderRules.testPathIssue(testPath), mono: true)
                }
                Text(
                    frozen
                        ? "Accounts use this provider, so how it speaks and its key prefix stay as they are."
                        : "Keys go to it only through Core's gateway, matched by their prefix. Without a test path, a key test answers Can't tell."
                )
                .font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary)
                .fixedSize(horizontal: false, vertical: true)
                modelsList
                Label(
                    "Its accounts can't join pools or chains yet. Models need a price to count as spend.",
                    systemImage: "info.circle"
                )
                .font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary)
                if let e = model.writeError["provider"] { AccIssue(text: e) }
                AccNotice(notice: model.host.elevationNotice)
                AccDialogButtons(
                    confirm: editing == nil ? "Add provider" : "Save", busy: busy, enabled: issue == nil, cancel: close
                ) { go() }
            }
        }
        .help(id.isEmpty ? "" : "id \(id)")
        .accessibilityIdentifier("provider-dialog")
    }

    /// The model ids, exactly as the provider names them, each with its list price.
    private var modelsList: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            CoreFieldLabel("Models")
            ForEach($models) { $m in
                HStack(spacing: Space.s2) {
                    Text(m.id).font(.system(size: MacTextSize.body, design: .monospaced)).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    PriceField(label: "in", micros: $m.input)
                    PriceField(label: "out", micros: $m.output)
                    Button {
                        withAnimation(.smooth(duration: 0.25)) { models.removeAll { $0.id == m.id } }
                    } label: {
                        Image(systemName: "xmark").frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain).foregroundStyle(GlassInk.secondary).help("Remove \(m.id)")
                }
                .padding(.horizontal, Space.s2).frame(minHeight: 36)
                .background(GlassInk.well, in: coreShape(Radius.control + 2))
                .transition(.opacity)
            }
            HStack(alignment: .top, spacing: Space.s2) {
                CoreTextField(
                    "", placeholder: "anthropic/claude-sonnet-4.5", text: $newModel,
                    error: newModel.isEmpty
                        ? nil
                        : models.contains { $0.id == newModel }
                            ? "Already listed." : ProviderRules.modelIssue(newModel),
                    mono: true
                ) { add() }
                AppActionTile(title: "Add model", symbol: "plus", key: "", hue: GlassInk.blue) { add() }
                    .disabled(ProviderRules.modelIssue(newModel) != nil || models.contains { $0.id == newModel })
            }
        }
    }

    private func add() {
        let m = newModel.trimmingCharacters(in: .whitespaces)
        guard ProviderRules.modelIssue(m) == nil, !models.contains(where: { $0.id == m }) else { return }
        withAnimation(.smooth(duration: 0.25)) { models.append(.init(id: m, input: 0, output: 0)) }
        newModel = ""
    }

    private func go() {
        guard issue == nil else { return }
        busy = true
        let d = ProviderDraft(
            id: id, name: name.trimmingCharacters(in: .whitespaces), harness: harness, baseURL: url, keyPrefix: prefix,
            testPath: testPath.isEmpty ? nil : testPath, models: models)
        Task {
            let ok = await model.saveProvider(d, replacing: editing != nil)
            busy = false
            if ok { close() }
        }
    }
}

/// Dollars per million tokens, typed; kept as millionths of a dollar.
private struct PriceField: View {
    let label: String
    @Binding var micros: Int64
    @State private var text = ""

    var body: some View {
        HStack(spacing: 4) {
            Text("$").foregroundStyle(GlassInk.secondary)
            TextField("0.00", text: $text).textFieldStyle(.plain).frame(width: 56).monospacedDigit()
                .onChange(of: text) { _, t in
                    if let d = AccountsNumbers.parseDecimal(t), d >= 0 {
                        micros = Int64((d * 1_000_000).rounded())
                    }
                }
            Text("\(label) / M").font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary)
        }
        .padding(.horizontal, Space.s2).frame(height: 28)
        .coreFieldSurface()
        .onAppear { text = micros == 0 ? "" : AccountsNumbers.dollarsField(micros) }
    }
}

struct DeleteProviderDialog: View {
    let model: AccountsModel
    let provider: ProviderItem
    let close: () -> Void
    @State private var busy = false

    var body: some View {
        CoreDialogPanel("Remove \(provider.name)?", width: Space.s8 * 14) {
            VStack(alignment: .leading, spacing: Space.s3) {
                Text("Its definition is deleted. Core refuses while an account still uses it.")
                    .fixedSize(horizontal: false, vertical: true)
                if let e = model.writeError["provider-\(provider.id)"] { AccIssue(text: e) }
                AccNotice(notice: model.host.elevationNotice)
                AccDialogButtons(confirm: "Remove provider", danger: true, busy: busy, cancel: close) {
                    busy = true
                    Task {
                        let ok = await model.deleteProvider(provider)
                        busy = false
                        if ok { close() }
                    }
                }
            }
        }
        .accessibilityIdentifier("provider-delete")
    }
}
