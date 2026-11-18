import CoreUI
import SwiftUI

/// The room card on a room's Overview (B10-02): what an AI session is told about this room when it starts, so the person
/// sees what the Brain hands over. Hidden when this Core has no card; a failure says so in place and offers Try Again.
struct RoomCardSection: View {
    let model: BrainModel
    let room: RoomSummary
    private var care: RoomCareModel { model.care }
    private var state: RoomCareModel.CardState { care.roomID == room.id ? care.card : .loading }

    var body: some View {
        Group {
            switch state {
            case .loading, .none:
                EmptyView()
            case .failed(let why):
                CoreNotice(symbol: "exclamationmark.triangle", title: "Unable to load the room card", text: why, tone: .warn)
                {
                    Button("Try Again") { Task { await care.loadCard(room.id) } }
                        .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                }
            case .ready(let card):
                BrainCard("Room card", sub: "What an AI session is told about this room when it starts.") {
                    ScrollView {
                        Text(card.text).coreFont(size: MacTextSize.body).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: Space.s8 * 7)
                    Text(
                        BrainWords.plural(card.records, "memory", "memories")
                            + (card.complete ? "" : " · cut to fit its size limit")
                    )
                    .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                }
            }
        }
        .task(id: room.id) { await care.loadCard(room.id) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("room-card")
    }
}
