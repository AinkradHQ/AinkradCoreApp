import Foundation

// The Environment tab's variables, of a configuration or (API 112) of the Default. A configuration's value can be shown on
// request; the Default's never can, the Core does not return one.
extension RunConfigsModel {
    func loadVars() async {
        revealed = [:]
        varsError = nil
        diff = []
        guard let service, !env.isEmpty, envReady else {
            vars = []
            return
        }
        do {
            if envIsDefault {
                vars = try await service.defaultVars(project: projectID, env: env)
                return
            }
            guard let c = envConfigItem else { return }
            vars = try await service.vars(project: projectID, config: c.id, env: env)
            if comparing, compareWith != env {
                diff = (try? await service.diff(project: projectID, config: c.id, a: env, b: compareWith)) ?? []
            }
        } catch {
            vars = []
            varsError = words(error)
        }
    }

    // MARK: variables

    /// The name as the Core takes it: upper case, spaces as `_`.
    static func varName(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespaces).uppercased().replacingOccurrences(of: " ", with: "_")
    }

    func addVar(key: String, value: String) async -> Bool {
        let k = Self.varName(key)
        guard !k.isEmpty else {
            model.host.shell.showToast("Give the variable a name first", kind: .warn)
            return false
        }
        return await setVar(k, value: value, secret: nil, done: "Added \(k)")
    }

    func link(_ v: RunVarItem, to secret: String) async {
        _ = await setVar(v.key, value: nil, secret: secret, done: "\(v.key) now comes from Secrets")
    }

    /// Back to a plain value: the value is gone with the link, so it is empty until set again.
    func unlink(_ v: RunVarItem) async {
        _ = await setVar(v.key, value: "", secret: nil, done: "\(v.key) is a plain value now")
    }

    func setValue(_ v: RunVarItem, _ value: String) async {
        _ = await setVar(v.key, value: value, secret: nil, done: nil)
    }

    @discardableResult
    private func setVar(_ key: String, value: String?, secret: String?, done: String?) async -> Bool {
        guard envReady else { return false }
        let (config, env, isDefault) = (envConfigItem?.id, self.env, envIsDefault)
        var ok = false
        await write("Change a variable of \(model.open?.name ?? "the project").") { service in
            if isDefault {
                try await service.setDefaultVar(
                    project: self.projectID, env: env, key: key, value: value, secret: secret)
            } else if let config {
                try await service.setVar(
                    project: self.projectID, config: config, env: env, key: key, value: value, secret: secret)
            }
            await self.loadVars()
            if let done { self.model.host.shell.showToast(done) }
            ok = true
        }
        return ok
    }

    func deleteVar(_ v: RunVarItem) async {
        guard envReady else { return }
        let (config, env, isDefault) = (envConfigItem?.id, self.env, envIsDefault)
        await write("Delete a variable of \(model.open?.name ?? "the project").") { service in
            if isDefault {
                try await service.deleteDefaultVar(project: self.projectID, env: env, key: v.key)
            } else if let config {
                try await service.deleteVar(project: self.projectID, config: config, env: env, key: v.key)
            }
            await self.loadVars()
            self.model.host.shell.showToast("Deleted \(v.key)")
        }
    }

    /// Show or hide a plain value. The value is read from the Core when shown and dropped when hidden.
    func toggleReveal(_ v: RunVarItem) async {
        if revealed[v.key] != nil {
            revealed[v.key] = nil
            return
        }
        guard let service, let c = envConfigItem, v.secret == nil else { return }
        do {
            revealed[v.key] = try await service.reveal(project: projectID, config: c.id, env: env, key: v.key)
        } catch {
            writeError = "Could not show \(v.key): \(words(error))"
            model.host.shell.showToast(writeError ?? "", kind: .warn)
        }
    }

    func importEnv(_ text: String) async -> Bool {
        guard let c = envConfigItem else { return false }
        var ok = false
        await write("Import variables into \(model.open?.name ?? "the project").") { service in
            let r = try await service.importEnv(project: self.projectID, config: c.id, env: self.env, text: text)
            await self.loadVars()
            let skipped = r.skipped > 0 ? ", \(r.skipped) skipped" : ""
            self.model.host.shell.showToast(
                "Imported \(ProjectItem.count(r.imported, "variable")) into \(self.env)\(skipped)")
            ok = true
        }
        return ok
    }
}
