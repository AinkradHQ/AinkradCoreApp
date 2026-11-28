import CoreKit
import Foundation

/// A 409 of the projects routes, told by cause. The Core answers every one with code `conflict` and one sentence (only a
/// missing GitHub connection has its own code), so the cause is read from the sentence.
enum ProjectConflict: Equatable {
    case slugTaken, linkLocked, archived, notArchived, repoExists, primaryRepo, noConnection, connectionOff
    case running, roomLinked
    case other(String)

    init(code: String?, message: String) {
        let m = message.lowercased()
        if code == "no_connection" {
            self = .noConnection
        } else if code == "project_running" {
            self = .running
        } else if code == "room_linked" {
            self = .roomLinked
        } else if code == "not_archived" {
            self = .notArchived
        } else if m.contains("connection is disabled") {
            self = .connectionOff
        } else if m.contains("slug exists") {
            self = .slugTaken
        } else if m.contains("link name is taken") {
            self = .linkLocked
        } else if m.contains("not archived") {
            self = .notArchived
        } else if m.contains("archived") {
            self = .archived
        } else if m.contains("repo of that name or remote") {
            self = .repoExists
        } else if m.contains("set another repo primary") {
            self = .primaryRepo
        } else {
            self = .other(message)
        }
    }

    /// The cause of a thrown error; nil when it is not a conflict.
    static func of(_ error: any Error) -> ProjectConflict? {
        guard let e = CoreFailure.of(error) ?? CoreError.unwrapping(error) else { return nil }
        if case .http(let status, let code, let message) = e,
            status == 409 || code == "conflict" || code == "no_connection"
        {
            return ProjectConflict(code: code, message: message)
        }
        return nil
    }

    var words: String {
        switch self {
        case .slugTaken: "That link name is taken. Pick another."
        case .linkLocked:
            "The link name can’t change now: it is taken, or the project is running or holds secrets."
        case .archived: "This project is archived. Unarchive it first."
        case .notArchived: "This project is not archived."
        case .running: "It is still running. Stop it first."
        case .roomLinked:
            "That Brain place already belongs to another project, maybe an archived one. Pick another place, or make a new one."
        case .repoExists: "This project already has that repo."
        case .primaryRepo: "Make another repo primary before removing this one."
        case .noConnection: "GitHub is not connected. Connect GitHub in Settings, Connections."
        case .connectionOff: "The GitHub connection is turned off. Turn it on in Connections."
        case .other(let m): m.isEmpty ? "The Core refused that." : m
        }
    }
}

/// Why the Core could not list GitHub's repos, in the words the picker shows.
enum CatalogProblem: Equatable, Sendable {
    /// No GitHub connection yet (409 `no_connection`).
    case noConnection
    /// GitHub refused the connection's token (502 `auth_failed`).
    case authFailed
    /// GitHub could not be reached (502 `unreachable`) or the Core did not answer.
    case unreachable
    case rateLimited
    case connectionOff
    case other(String)

    init(_ error: any Error) {
        let e = CoreFailure.of(error) ?? CoreError.unwrapping(error)
        switch e {
        case .http(_, "no_connection", _)?: self = .noConnection
        case .http(_, "auth_failed", _)?: self = .authFailed
        case .http(_, "unreachable", _)?: self = .unreachable
        case .http(_, "rate_limited", _)?, .rateLimited?: self = .rateLimited
        case .offline?: self = .unreachable
        case .http(409, _, let m)?:
            self = ProjectConflict(code: nil, message: m) == .connectionOff ? .connectionOff : .other(m)
        case let e?: self = .other(e.localizedDescription)
        case nil: self = .other(error.localizedDescription)
        }
    }

    var words: String {
        switch self {
        case .noConnection: "Connect GitHub so Core can list your repos."
        case .authFailed: "GitHub no longer accepts the connection. Connect GitHub again."
        case .unreachable: "GitHub can’t be reached right now. Try again in a moment."
        case .rateLimited: "GitHub is limiting requests. Try again in a minute."
        case .connectionOff: "The GitHub connection is turned off. Turn it on in Connections."
        case .other(let m): "The Core could not list your repos: \(m)"
        }
    }

    /// The fix is in Connections, not another try.
    var needsConnection: Bool { self == .noConnection || self == .authFailed || self == .connectionOff }
}

/// A repo the Core would not take, with the reason in words (the review step and the toast list these).
struct MissedRepo: Equatable, Identifiable, Sendable {
    let name: String
    let why: String
    var id: String { name }
}
