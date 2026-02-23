import Foundation

enum TydomMessageEffect: Sendable, Equatable {
    case sendCommands([TydomCommand])
    case pongReceived
    case cdataReplyChunk(TydomCDataReplyChunk)
}

struct TydomCDataReplyChunk: Sendable, Equatable {
    let transactionId: String
    let events: [JSONValue]
    let done: Bool

    init(transactionId: String, events: [JSONValue], done: Bool) {
        self.transactionId = transactionId
        self.events = events
        self.done = done
    }
}
