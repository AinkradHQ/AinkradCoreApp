import CoreUI
import SwiftUI

/// The project's secrets, as a list on one grid: name, when it was set, a menu. A secret the setup asks for and nobody set yet
/// has its Set… in view; the rest (Replace…, Delete…) is in the row menu. It lives in the Environment tab (and in the earlier
/// Run page of a Core without configurations): secrets are values a run is given, like the environment's variables.
struct SecretsIsland: View {
    let model: ProjectsModel
    let project: ProjectItem
    let run: RunPageModel

    var body: some View {
        let rows = run.secretRows
        Island(
            title: "Secrets", sub: rows.isEmpty ? nil : "\(rows.count)",
            accessory: {
                Button {
                    RunDialogs.openSecret(run, project: project, name: nil, replacing: false)
                } label: {
                    Label("Add…", systemImage: "plus")
                }
                .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                .disabled(model.readOnly || !run.loaded)
                .help("Add a secret the setup can use as ${secret:NAME}")
                .accessibilityIdentifier("project-add-secret")
            }
        ) {
            VStack(alignment: .leading, spacing: Space.s3) {
                if rows.isEmpty {
                    Text("No secrets yet. The setup asks for one by writing ${secret:NAME}; add it here.")
                        .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
                }
                ScrollView {
                    VStack(spacing: Space.s1) {
                        ForEach(rows) { r in
                            SecretRowView(model: model, project: project, run: run, row: r)
                                .transition(.opacity)
                        }
                        Text("Sealed in the Core and given to the run at start. Never shown again.")
                            .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
                            .padding(.top, Space.s2).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .animation(Motion.out(Motion.ui), value: rows.map(\.name))
                }
            }
        }
    }
}

private struct SecretRowView: View {
    let model: ProjectsModel
    let project: ProjectItem
    let run: RunPageModel
    let row: RunPageModel.SecretRow
    @State private var open = false

    private var kind: String? {
        guard let k = row.item?.kind, k != "text" else { return nil }
        return SecretSheet.kinds.first { $0.value == k }?.title ?? k
    }

    var body: some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "key").foregroundStyle(GlassInk.secondary).frame(width: MacSize.controlMd)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name).font(.system(size: MacTextSize.body, design: .monospaced)).lineLimit(1)
                    .truncationMode(.middle).help(row.name)
                Group {
                    if let at = row.item?.updatedAt {
                        Text("Set \(PickRepo.ago(at, model.now()))\(kind.map { " · \($0)" } ?? "")")
                            .foregroundStyle(GlassInk.secondary)
                    } else if row.item == nil {
                        Text("Not set").foregroundStyle(GlassInk.redInk)
                    }
                }
                .coreFont(size: MacTextSize.meta).lineLimit(1)
            }
            Spacer(minLength: 0)
            if row.item == nil {
                Button("Set…") {
                    RunDialogs.openSecret(run, project: project, name: row.name, replacing: false)
                }
                .buttonStyle(CoreButtonStyle(.secondary, size: .small)).disabled(model.readOnly).fixedSize()
                .accessibilityLabel("Set \(row.name)")
            } else {
                CoreDropdown(items: items, isPresented: $open) {
                    Image(systemName: "ellipsis").frame(width: MacSize.controlMd, height: MacSize.controlMd)
                }
                .accessibilityLabel("More for \(row.name)")
            }
        }
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
        .frame(maxWidth: .infinity, minHeight: MacSize.controlLg)
        .coreCard(GlassInk.well, radius: Radius.row)
    }

    private var items: [CoreDropdownItem] {
        [
            CoreDropdownItem("Replace…", symbol: "arrow.triangle.2.circlepath", enabled: !model.readOnly) {
                RunDialogs.openSecret(
                    run, project: project, name: row.name, replacing: true, kind: row.item?.kind ?? "text")
            },
            CoreDropdownItem("Delete…", symbol: "trash", destructive: true, enabled: !model.readOnly) {
                RunDialogs.confirmDelete(run, project: project, name: row.name)
            },
        ]
    }
}
