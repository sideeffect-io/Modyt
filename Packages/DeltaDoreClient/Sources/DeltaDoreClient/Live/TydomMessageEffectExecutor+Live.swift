import Foundation

extension TydomMessageEffectExecutor {
    static func live(
        sendCommand: @escaping @Sendable (TydomCommand) async throws -> Void,
        pongStore: TydomPongStore = TydomPongStore(),
        cdataReplyStore: TydomCDataReplyStore = TydomCDataReplyStore(),
        log: @escaping @Sendable (String) -> Void = { _ in }
    ) -> TydomMessageEffectExecutor {
        let dependencies = Dependencies(
            sendCommand: sendCommand,
            onPong: {
                await pongStore.markPongReceived()
            },
            onCDataReplyChunk: { chunk in
                await cdataReplyStore.append(chunk)
            },
            log: log
        )
        return TydomMessageEffectExecutor(dependencies: dependencies)
    }
}
