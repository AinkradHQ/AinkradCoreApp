import CoreUI
import Shell
import SwiftUI

/// The Environment tab: one environment's variables for one configuration. A value is hidden (dots) until Show is pressed on a
/// plain one; a variable linked to Secrets shows where it comes from and has no value to show. Compare lists what differs
/// between two environments, by name only.
struct EnvironmentTab: View {
    let runs: RunConfigsModel
    @State private var newKey = ""
    @State private var newValue = ""
    @State private var removing = false

    var body: some View {
        VStack(spacing: Space.s2) {
            controls
            if runs.comparing { compare } else { variables }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .coreConfirm(
            "Remove the \(runs.env) environment?", isPresented: $removing,
            message: "Its variables go with it. A run that is going keeps going.", confirmTitle: "Remove",
            destructive: true
        ) {
            let name = runs.env
            Task { await runs.removeEnvironment(name) }
        }
    }

    private var controls: some View {
        HStack(spacing: Space.s3) {
            CoreSegmented(
                "Environment", segments: runs.envs.map { CoreSegment($0, $0) },
                selection: Binding(get: { runs.env }, set: { e in Task { await runs.pickEnv(e) } }))
            Button {
                Task { await runs.addEnvironment() }
            } label: {
                Label("Environment", systemImage: "plus")
            }
            .buttonStyle(CoreButtonStyle(.plain, size: .small)).disabled(runs.model.readOnly || runs.busy)
            Button {
                removing = true
            } label: {
                Label("Remove", systemImage: "minus")
            }
            .buttonStyle(CoreButtonStyle(.plain, size: .small))
            .disabled(runs.model.readOnly || runs.busy || runs.envs.count < 2)
            .help(
                runs.envs.count < 2
                    ? "A project keeps at least one environment"
                    : runs.env == runs.defaultEnv
                        ? "\(runs.env) is the project's default; pick another default in Project Settings first"
                        : "Remove the \(runs.env) environment")
            Spacer(minLength: 0)
            if runs.configs.count > 1 {
                CoreSelect(
                    nil,
                    selection: Binding(
                        get: { runs.envConfigItem?.id ?? 0 }, set: { id in Task { await runs.pickConfig(id) } }),
                    options: runs.configs.map { CoreSelectOption($0.id, $0.name) }
                )
                .frame(width: Space.s8 * 4)
            }
            Button {
                RunsDialogs.openImport(runs)
            } label: {
                Label("Import .env", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(CoreButtonStyle(.secondary, size: .small))
            .disabled(runs.model.readOnly || runs.envConfigItem == nil)
            Button {
                Task { await runs.toggleCompare() }
            } label: {
                Label("Compare", systemImage: "arrow.left.arrow.right")
            }
            .buttonStyle(CoreButtonStyle(runs.comparing ? .prominent : .secondary, size: .small))
            .disabled(runs.envs.count < 2)
        }
    }

    private var variables: some View {
        Island(
            title: "\(runs.env) variables for \(runs.envConfigItem?.name ?? "")",
            accessory: { Text(runs.varsLine).foregroundStyle(GlassInk.secondary) }
        ) {
            if runs.envConfigItem == nil {
                Text("Add a configuration first.").foregroundStyle(GlassInk.secondary)
            } else {
                ScrollView {
                    VStack(spacing: Space.s1) {
                        if runs.vars.isEmpty {
                            Text("No variables in this environment yet.").foregroundStyle(GlassInk.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        ForEach(runs.vars) { v in VarRow(runs: runs, v: v) }
                        adder
                    }
                }
            }
        }
    }

    private var adder: some View {
        HStack(alignment: .bottom, spacing: Space.s2) {
            CoreTextField("Name", placeholder: "NAME", text: $newKey, mono: true)
                .frame(width: Space.s8 * 5)
            CoreSecureField("Value", placeholder: "Value", text: $newValue, onSubmit: add)
            Button("Add variable", action: add)
                .buttonStyle(CoreButtonStyle(.secondary)).disabled(runs.model.readOnly || runs.busy)
        }
        .padding(.top, Space.s2)
    }

    private func add() {
        let (k, v) = (newKey, newValue)
        Task {
            if await runs.addVar(key: k, value: v) {
                newKey = ""
                newValue = ""
            }
        }
    }

    private var compare: some View {
        Island(
            title: "\(runs.env) compared with",
            accessory: {
                CoreSelect(
                    nil,
                    selection: Binding(get: { runs.compareWith }, set: { e in Task { await runs.pickCompare(e) } }),
                    options: runs.envs.filter { $0 != runs.env }.map { CoreSelectOption($0, $0) }
                )
                .frame(width: Space.s8 * 4)
                Text("\(runs.differences) differences").foregroundStyle(GlassInk.secondary)
            }
        ) {
            ScrollView {
                VStack(spacing: Space.s1) {
                    if runs.diff.isEmpty { Text("Nothing to compare.").foregroundStyle(GlassInk.secondary) }
                    ForEach(runs.diff) { d in
                        CoreRow(
                            d.key,
                            symbol: d.change == .same
                                ? "checkmark" : d.change == .different ? "arrow.triangle.2.circlepath" : "plus"
                        ) {
                            StateBadge(
                                label(d.change), tone: d.change == .same ? .queue : d.change == .onlyA ? .run : .warn,
                                symbol: "circle")
                        }
                    }
                }
            }
        }
    }

    private func label(_ c: EnvDiffItem.Change) -> String {
        switch c {
        case .same: "Same"
        case .different: "Different"
        case .onlyA: "Only in \(runs.env)"
        case .onlyB: "Only in \(runs.compareWith)"
        }
    }
}

private struct VarRow: View {
    let runs: RunConfigsModel
    let v: RunVarItem
    @State private var menu = false

    private var shown: String? { runs.revealed[v.key] }

    private var line: String {
        if v.secret != nil { return "Value comes from Secrets" }
        return shown ?? String(repeating: "•", count: min(12, max(6, v.size)))
    }

    var body: some View {
        HStack(spacing: Space.s3) {
            Image(systemName: v.secret == nil ? "doc.text" : "key").foregroundStyle(GlassInk.secondary)
                .frame(width: MacSize.controlMd).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(v.key).font(.system(size: MacTextSize.body, design: .monospaced)).lineLimit(1)
                Text(line).font(.system(size: MacTextSize.meta, design: .monospaced)).foregroundStyle(
                    GlassInk.secondary
                )
                .lineLimit(1).textSelection(.enabled)
            }
            Spacer(minLength: 0)
            Text(v.secret.map { "From Secrets: \($0)" } ?? "Plain value").foregroundStyle(GlassInk.secondary)
                .coreFont(size: MacTextSize.meta)
            if v.secret == nil {
                CoreIconButton(
                    symbol: shown == nil ? "eye" : "eye.slash",
                    label: shown == nil ? "Show the value" : "Hide the value"
                ) {
                    Task { await runs.toggleReveal(v) }
                }
            }
            CoreDropdown(items: items, isPresented: $menu) {
                Image(systemName: "ellipsis").frame(width: MacSize.controlMd, height: MacSize.controlMd)
            }
            .accessibilityLabel("More for \(v.key)")
        }
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
        .frame(maxWidth: .infinity, minHeight: MacSize.controlLg)
        .coreCard(GlassInk.well, radius: Radius.row)
    }

    private var items: [CoreDropdownItem] {
        var out: [CoreDropdownItem] = []
        if v.secret == nil {
            out.append(
                CoreDropdownItem(shown == nil ? "Show the value" : "Hide the value", symbol: "eye") {
                    Task { await runs.toggleReveal(v) }
                })
            out.append(
                CoreDropdownItem(
                    "Link to a Secret", symbol: "key", enabled: !runs.secretNames.isEmpty && !runs.model.readOnly,
                    note: runs.secretNames.isEmpty ? "none yet" : nil
                ) {})
            out += runs.secretNames.map { s in
                CoreDropdownItem("Use \(s)", enabled: !runs.model.readOnly, indented: true) {
                    Task { await runs.link(v, to: s) }
                }
            }
        } else {
            out.append(
                CoreDropdownItem("Unlink from Secrets", symbol: "link", enabled: !runs.model.readOnly) {
                    Task { await runs.unlink(v) }
                })
        }
        out.append(
            CoreDropdownItem("Delete variable", symbol: "trash", destructive: true, enabled: !runs.model.readOnly) {
                Task { await runs.deleteVar(v) }
            })
        return out
    }
}

@MainActor
enum RunsDialogs {
    static func openImport(_ runs: RunConfigsModel) {
        let shell = runs.model.host.shell
        shell.present(ShellDialog(id: "project-import-env") { ImportEnvSheet(runs: runs) { shell.closeDialog() } })
    }
}

/// Import a .env file: paste the text. Values become plain variables of the open environment and stay hidden.
struct ImportEnvSheet: View {
    let runs: RunConfigsModel
    let close: () -> Void
    @State private var text = ""

    /// Lines that look like `KEY=value`, for the button's count.
    static func count(_ text: String) -> Int {
        text.split(whereSeparator: \.isNewline).filter {
            let l = $0.trimmingCharacters(in: .whitespaces)
            return !l.hasPrefix("#") && l.contains("=")
        }.count
    }

    var body: some View {
        CoreDialogPanel("", width: Space.s8 * 14) {
            VStack(alignment: .leading, spacing: Space.s4) {
                DialogHead(
                    title: "Import a .env file",
                    line: "Paste the file. Values stay hidden once imported, and go into \(runs.env).")
                CoreTextArea(
                    nil, placeholder: "API_URL=http://localhost:8080", text: $text, autofocus: true, design: .monospaced
                )
                CoreDialogFooter(
                    cancel: CoreAction("Cancel", key: .cancel, run: close),
                    primary: CoreAction(
                        Self.count(text) == 0 ? "Import" : "Import \(ProjectItem.count(Self.count(text), "variable"))",
                        key: .primary
                    ) {
                        let t = text
                        Task { if await runs.importEnv(t) { close() } }
                    }, busy: runs.busy, enabled: Self.count(text) > 0)
            }
        }
        .accessibilityIdentifier("project-import-env")
    }
}
