import CoreKit
import Foundation

/// What the Core's API 95 gives the session screens: the folder tree, per-file revert, writing a file, effort, and "always allow
/// for this project". Where the Core is older (the call is not offered) each one falls back to the conversation or says so.
extension AgentsModel {
    func refreshSessionTools() async {
        guard let api else { return }
        let has = await api.hasSessionTools()
        if has != sessionTools { sessionTools = has }
    }

    // MARK: folder

    /// Lists one directory of the session's folder, once (a second ask answers from what is held unless `force`).
    func listFolder(_ id: String, dir: String = "", force: Bool = false) async {
        guard let api else { return }
        if !force, folders[id]?[dir] != nil { return }
        do {
            let l = try await api.folder(id, dir: dir)
            folders[id, default: [:]][dir] = l
        } catch {
            // A Core without the route, or a folder that is gone: the tree shows nothing for it.
            if folders[id]?[dir] == nil { folders[id, default: [:]][dir] = FolderListing(dir: dir, entries: []) }
        }
    }

    /// The names under `dir` that start with `prefix`, folders first: what the @ picker offers. Loads the directory on first ask.
    func mentionMatches(_ id: String, dir: String, prefix: String) -> [FolderEntry] {
        let all = folders[id]?[dir]?.entries ?? []
        let q = prefix.lowercased()
        return all.filter { q.isEmpty || $0.name.lowercased().hasPrefix(q) }
    }

    // MARK: revert and write

    /// Puts files back as they were before this session's edits. A Core without the route gets the request in the conversation.
    func revert(_ id: String, paths: [String]) async {
        guard let api else { return }
        note(id, nil)
        for path in paths {
            do {
                let s = try await elevated("Revert a file this AI session changed.") { try await api.revert(id, path: path) }
                sessions.upsert(s)
                ReviewStore.shared.set(id, path, .reverted)
            } catch let e as ElevationDeclined {
                note(id, e.notice)
                return
            } catch {
                if case .forbiddenScope? = CoreError.unwrapping(error) {
                    ReviewStore.shared.set(id, path, .revertAsked)
                    await say(id, "Please revert your changes to `\(path)` and tell me when it is done.")
                } else {
                    note(id, Self.notice(error, doing: "Reverting \((path as NSString).lastPathComponent)"))
                    return
                }
            }
        }
        await refreshSession(id)
    }

    /// Apply: writes a code block into a file of the session's folder.
    func writeFile(_ id: String, path: String, content: String) async {
        guard let api else { return }
        note(id, nil)
        do {
            let s = try await elevated("Write a file in this AI session's folder.") {
                try await api.writeFile(id, path: path, content: content)
            }
            sessions.upsert(s)
            shell.showToast("Wrote \((path as NSString).lastPathComponent)")
            await refreshSession(id)
        } catch let e as ElevationDeclined {
            note(id, e.notice)
        } catch {
            if case .forbiddenScope? = CoreError.unwrapping(error) {
                await say(id, "Please write this to `\(path)`:\n\n```\n\(content)\n```")
            } else {
                note(id, Self.notice(error, doing: "Writing \((path as NSString).lastPathComponent)"))
            }
        }
    }

    // MARK: effort and always-allow

    func setEffort(_ id: String, _ effort: String) async {
        guard let api else { return }
        note(id, nil)
        do {
            let s = try await elevated("Change how hard the AI session thinks.") { try await api.setEffort(id, effort) }
            sessions.upsert(s)
        } catch let e as ElevationDeclined {
            note(id, e.notice)
        } catch { note(id, Self.notice(error, doing: "Changing the effort")) }
    }

    /// Approve this request and every like it in this project from now on.
    func approveAlways(_ r: ApprovalRequest) async {
        guard let api else { return }
        deciding.insert(r.id)
        defer { deciding.remove(r.id) }
        do {
            let s = try await elevated("Always allow this for the project.") {
                try await api.decideAlways(r.session, request: r.id)
            }
            sessions.upsert(s)
            await refreshSession(r.session)
        } catch let e as ElevationDeclined {
            approvalNotices[r.id] = e.notice
        } catch {
            approvalNotices[r.id] = Self.notice(error, doing: "Saving the rule")
        }
    }
}

/// The effort levels the Core takes, lowest first.
enum Effort {
    static let all: [(id: String, title: String, note: String)] = [
        ("low", "Low", "quick, light thinking"), ("medium", "Medium", "balanced"),
        ("high", "High", "careful"), ("max", "Max", "as long as it needs"),
    ]
    static func title(_ id: String?) -> String { all.first { $0.id == id }?.title ?? "Default" }
}
