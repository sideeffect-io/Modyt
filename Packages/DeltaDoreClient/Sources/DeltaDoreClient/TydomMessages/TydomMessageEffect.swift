import Foundation

enum TydomMessageEffect: Sendable, Equatable {
    case sendCommands([TydomCommand])
    case pongReceived
    case cdataReplyChunk(TydomCDataReplyChunk)
}

struct TydomCDataReplyChunk: Sendable, Equatable {
    let transactionId: String
    let events: [PayloadValue]
    let done: Bool

    init(transactionId: String, events: [PayloadValue], done: Bool) {
        self.transactionId = transactionId
        self.events = events
        self.done = done
    }
}
