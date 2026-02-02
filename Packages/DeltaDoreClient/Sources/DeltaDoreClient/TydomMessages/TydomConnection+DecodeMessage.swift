import Foundation

extension TydomConnection {
    public func decodedMessages() -> AsyncStream<TydomMessage> {
        decodedMessages(logger: { _ in })
    }

    public func decodedMessages(
        logger: @escaping @Sendable (String) -> Void
    ) -> AsyncStream<TydomMessage> {
        let dependencies = TydomMessagePipelineDependencies.live(connection: self, log: logger)
        return AsyncStream { continuation in
            let task = Task { [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }
                for await data in await self.messages() {
                    let raw = dependencies.dataToRawMessage(data)
                    if let parseError = raw.parseError {
                        let snippet = String(data: raw.payload.prefix(200), encoding: .isoLatin1)
                            ?? String(decoding: raw.payload.prefix(200), as: UTF8.self)
                        logger("Decode parse error=\(parseError) bytes=\(raw.payload.count) snippet=\(snippet)")
                    }
                    let decoded = dependencies.rawMessageToEnvelope(raw)
                    let hydrated = await dependencies.hydrateFromCache(decoded)
                    Task { await dependencies.enqueueEffects(hydrated.effects) }
                    continuation.yield(hydrated.message)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

struct TydomMessagePipelineDependencies: Sendable {
    let dataToRawMessage: @Sendable (Data) -> TydomRawMessage
    let rawMessageToEnvelope: @Sendable (TydomRawMessage) -> TydomDecodedEnvelope
    let hydrateFromCache: @Sendable (TydomDecodedEnvelope) async -> TydomHydratedEnvelope
    let enqueueEffects: @Sendable ([TydomMessageEffect]) async -> Void

    init(
        dataToRawMessage: @escaping @Sendable (Data) -> TydomRawMessage,
        rawMessageToEnvelope: @escaping @Sendable (TydomRawMessage) -> TydomDecodedEnvelope,
        hydrateFromCache: @escaping @Sendable (TydomDecodedEnvelope) async -> TydomHydratedEnvelope,
        enqueueEffects: @escaping @Sendable ([TydomMessageEffect]) async -> Void
    ) {
        self.dataToRawMessage = dataToRawMessage
        self.rawMessageToEnvelope = rawMessageToEnvelope
        self.hydrateFromCache = hydrateFromCache
        self.enqueueEffects = enqueueEffects
    }
}
