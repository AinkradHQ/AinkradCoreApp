import AinkradClient
import CoreKit
import Foundation

// The Core's API 95 routes for the AI session screens. They use operations that exist in the generated client only after the
// coordinator regenerates it for API 95 (`make clients`), so they build behind `CORE_CLIENT_95`: add that to the Agents target's
// Swift flags when the client is synced. Until then a Core call falls back to the protocol defaults (not offered).
#if CORE_CLIENT_95
    extension LiveAgentsAPI {
        public func hasSessionTools() async -> Bool { await connection.serverSupports(minor: 95) }

        public func folder(_ id: String, dir: String) async throws -> FolderListing {
            try await run {
                switch try await client.listAgentSessionFiles(path: .init(id: id), query: .init(dir: dir)) {
                case .ok(let o):
                    let l = try o.body.json
                    return FolderListing(
                        dir: l.dir, entries: l.entries.map { FolderEntry(name: $0.name, dir: $0.dir, size: $0.size) },
                        truncated: l.truncated)
                case .badRequest(let r): throw Self.fail(r)
                case .notFound(let r): throw Self.fail(r)
                case .conflict(let r): throw Self.fail(r)
                case .undocumented(let status, let p): throw await Self.status(status, p)
                default: throw Self.unknown
                }
            }
        }

        public func revert(_ id: String, path: String) async throws -> AgentSessionInfo {
            try await run {
                switch try await client.revertAgentFile(path: .init(id: id), body: .json(.init(path: path))) {
                case .ok(let o): return Self.session(try o.body.json)
                case .badRequest(let r): throw Self.fail(r)
                case .notFound(let r): throw Self.fail(r)
                case .conflict(let r): throw Self.fail(r)
                case .undocumented(let status, let p): throw await Self.status(status, p)
                default: throw Self.unknown
                }
            }
        }

        public func writeFile(_ id: String, path: String, content: String) async throws -> AgentSessionInfo {
            try await run {
                switch try await client.writeAgentFile(
                    path: .init(id: id), body: .json(.init(content: content, path: path)))
                {
                case .ok(let o): return Self.session(try o.body.json)
                case .badRequest(let r): throw Self.fail(r)
                case .notFound(let r): throw Self.fail(r)
                case .conflict(let r): throw Self.fail(r)
                case .undocumented(let status, let p): throw await Self.status(status, p)
                default: throw Self.unknown
                }
            }
        }

        public func setEffort(_ id: String, _ effort: String) async throws -> AgentSessionInfo {
            try await run {
                let body = Components.Schemas.AgentModeChange(effort: effort)
                switch try await client.setAgentSessionMode(path: .init(id: id), body: .json(body)) {
                case .ok(let o): return Self.session(try o.body.json)
                case .badRequest(let r): throw Self.fail(r)
                case .notFound(let r): throw Self.fail(r)
                case .conflict(let r): throw Self.fail(r)
                case .undocumented(let status, let p): throw await Self.status(status, p)
                default: throw Self.unknown
                }
            }
        }

        public func decideAlways(_ id: String, request: String) async throws -> AgentSessionInfo {
            try await run {
                switch try await client.decideAgentApproval(
                    path: .init(id: id, request: request), body: .json(.init(always: true, approved: true)))
                {
                case .ok(let o): return Self.session(try o.body.json)
                case .badRequest(let r): throw Self.fail(r)
                case .notFound(let r): throw Self.fail(r)
                case .conflict(let r): throw Self.fail(r)
                case .undocumented(let status, let p): throw await Self.status(status, p)
                default: throw Self.unknown
                }
            }
        }
    }
#endif
