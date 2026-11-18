import Admin
import CoreKit
import Foundation

/// The way into the import dialogs. The Lore space calls these; Projects' Docs page (R6-06) calls `fromRepo`.
public enum LoreImport {
    /// True when this Core connection can import (a test double or an old Core cannot).
    public static func supports(_ service: (any LoreService)?) -> Bool { service is any LoreImportService }

    /// The chooser: from a repo, from files, or the earlier imports.
    @MainActor public static func chooser(
        host: any AdminHost, service: (any LoreService)?, projects: [String: String], project: String? = nil
    ) {
        model(host, service, projects, project)?.present()
    }

    /// Straight to the repo form for `project`.
    @MainActor public static func fromRepo(
        host: any AdminHost, service: (any LoreService)?, projects: [String: String], project: String? = nil
    ) {
        guard let m = model(host, service, projects, project) else { return }
        m.phase = .repoSetup
        m.present()
    }

    @MainActor private static func model(
        _ host: any AdminHost, _ service: (any LoreService)?, _ projects: [String: String], _ project: String?
    ) -> LoreImportModel? {
        guard let service = service as? any LoreImportService else { return nil }
        return LoreImportModel(host: host, service: service, projectNames: projects, project: project ?? "")
    }
}
