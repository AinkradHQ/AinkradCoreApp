import Foundation

extension AgentsModel {
    /// Steer: redirect a running turn. The turn in flight is stopped (the CLI's Esc), then the message goes as the next turn
    /// at once, ahead of the queue. A tool that cannot be interrupted is not offered it (`canStopTurn`).
    public func steer(_ id: String) async {
        guard let api, let s = sessions.session(id), canStopTurn(s), canSend(id) else { return }
        note(id, nil)
        do {
            let stopped = try await api.stopTurn(id)
            sessions.upsert(stopped)
            syncDerived()
        } catch {
            note(id, Self.notice(error, doing: "Stopping the turn"))
            return
        }
        await send(id)
    }
}
