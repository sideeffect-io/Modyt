import Foundation

extension TydomConnection {
    public func decodedMessages() -> AsyncStream<TydomMessage> {
        decodedMessages(logger: { _ in }, rawFrameHandler: { _ in })
    }

    public func decodedMessages(
        logger: @escaping @Sendable (String) -> Void,
        rawFrameHandler: @escaping @Sendable (TydomRawMessage) -> Void = { _ in }
    ) -> AsyncStream<TydomMessage> {
        let hydrator = TydomMessageHydrator.live(log: logger)
        let effectExecutor = TydomMessageEffectExecutor.live(
            sendCommand: { [weak self] command in
                guard let self else { return }
                try await self.send(command)
            },
            log: logger
        )

        return AsyncStream { continuation in
            let task = Task { [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }
                for await data in await self.rawMessages() {
                    let cleanData: Data
                    if let prefix = self.configuration.commandPrefix, data.first == prefix {
                        cleanData = Data(data.dropFirst())
                    } else {
                        cleanData = data
                    }
                    let parsed = TydomRawMessageParser.parse(cleanData)
                    let raw = TydomRawMessage(
                        payload: data,
                        frame: parsed.frame,
                        uriOrigin: parsed.uriOrigin,
                        transactionId: parsed.transactionId,
                        parseError: parsed.parseError
                    )
                    rawFrameHandler(raw)
                    if let parseError = raw.parseError {
                        let snippet = String(data: raw.payload.prefix(200), encoding: .isoLatin1)
                            ?? String(decoding: raw.payload.prefix(200), as: UTF8.self)
                        logger("Decode parse error=\(parseError) bytes=\(raw.payload.count) snippet=\(snippet)")
                    }

                    let decoded = TydomMessageDecoder.decode(raw)
                    let hydrated = await hydrator.hydrate(decoded)
                    await effectExecutor.enqueue(hydrated.effects)
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
