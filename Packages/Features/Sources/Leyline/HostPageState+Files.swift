import Admin
import AppKit
import Foundation
import Shell
import UniformTypeIdentifiers

// Files moving between this Mac and the host: a drag out to Finder, Download, Upload and a drop in.
extension HostPageState {
    /// Where a drag out gets its bytes: a real file in a temporary folder, made when Finder asks.
    nonisolated static func provider(for f: RemoteFile, host: String, service: any LeylineService) -> NSItemProvider {
        let p = NSItemProvider()
        let name = RemotePath.safeName(f.name)
        p.suggestedName = name
        p.registerFileRepresentation(forTypeIdentifier: UTType.data.identifier, fileOptions: [], visibility: .all) {
            done in
            nonisolated(unsafe) let done = done  // called once, from the one task below
            Task {
                do {
                    let d = try await service.download(host: host, path: f.path)
                    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(
                        UUID().uuidString, isDirectory: true)
                    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    let url = dir.appendingPathComponent(name)
                    try d.write(to: url, options: .atomic)
                    done(url, true, nil)
                } catch { done(nil, false, error) }
            }
            return nil
        }
        return p
    }

    func dragProvider(_ f: RemoteFile) -> NSItemProvider {
        guard let service, f.kind == .file else { return NSItemProvider() }
        return Self.provider(for: f, host: hostID, service: service)
    }

    /// Saves the file with the system panel ("Download").
    func download(_ f: RemoteFile) async {
        guard let service else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = RemotePath.safeName(f.name)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        transfer = "Downloading \(f.name)…"
        defer { transfer = nil }
        do {
            try await service.download(host: hostID, path: f.path).write(to: url, options: .atomic)
            shell.showToast("\(f.name) saved")
        } catch { shell.showToast(words(error), kind: .warn) }
    }

    /// "Upload…": the system panel, then the same path a drop takes.
    func chooseUpload() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        upload(panel.urls)
    }

    /// Files dropped in or chosen: folders are skipped, and a name that is already there asks before it is replaced.
    func upload(_ urls: [URL]) {
        guard model.mayWrite() else { return }
        let files = urls.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true }
        if files.count < urls.count { shell.showToast("Folders are not uploaded here. Drop files.", kind: .warn) }
        guard !files.isEmpty else { return }
        let have = Set((entries.value ?? []).map(\.name))
        let clash = files.filter { have.contains(RemotePath.safeName($0.lastPathComponent)) }
        guard !clash.isEmpty else { return start(files) }
        shell.presentSheet(
            title: clash.count == 1 ? "Replace “\(clash[0].lastPathComponent)”?" : "Replace \(clash.count) files?",
            message: "They already exist in \(path) on \(host?.name ?? "the host"). The old versions are overwritten.",
            actions: [
                ShellSheetAction("Cancel"),
                ShellSheetAction("Replace", destructive: true) { [weak self] in self?.start(files) },
            ])
    }

    private func start(_ files: [URL]) {
        Task {
            guard let service else { return }
            for url in files {
                let name = RemotePath.safeName(url.lastPathComponent)
                transfer = "Uploading \(name)…"
                do {
                    let data = try await Task.detached { try Data(contentsOf: url) }.value
                    // Writing a file on a host needs Touch ID, like a terminal.
                    try await model.host.elevated(
                        "Write \(name) to \(host?.name ?? "the host").", done: "written", keepsEdit: false
                    ) { try await service.upload(host: hostID, path: RemotePath.join(path, name), data: data) }
                } catch is AdminDeclined {
                    transfer = nil
                    return
                } catch {
                    transfer = nil
                    shell.showToast(words(error), kind: .warn)
                    await loadFiles()
                    return
                }
            }
            transfer = nil
            shell.showToast(files.count == 1 ? "Uploaded" : "Uploaded \(files.count) files")
            await loadFiles()
        }
    }
}
