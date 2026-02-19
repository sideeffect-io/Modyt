import Foundation

extension TydomMessagePipelineDependencies {
    static func live(
        hydrator: TydomMessageHydrator = .live(),
        effectExecutor: TydomMessageEffectExecutor
    ) -> TydomMessagePipelineDependencies {
        TydomMessagePipelineDependencies(
            dataToRawMessage: { data in
                TydomRawMessageParser.parse(data)
            },
            rawMessageToEnvelope: { raw in
                TydomMessageDecoder.decode(raw)
            },
            hydrateFromCache: { decoded in
                await hydrator.hydrate(decoded)
            },
            enqueueEffects: { effects in
                await effectExecutor.enqueue(effects)
            }
        )
    }

    static func live(
        connection: TydomConnection,
        log: @escaping @Sendable (String) -> Void = { _ in }
    ) -> TydomMessagePipelineDependencies {
        let hydrator: TydomMessageHydrator = .live(
            isPostPutPollingActive: { [weak connection] uniqueId in
                await connection?.isPostPutPollingActive(uniqueId: uniqueId) ?? false
            },
            log: log
        )

        let pollScheduler = TydomMessagePollScheduler { [weak connection] command in
            guard let connection else { return }
            try await connection.send(command)
        } isActive: {
            [weak connection] in
            await connection?.isAppActive() ?? false
        }

        let effectExecutor = TydomMessageEffectExecutor.live(
            pollingConfiguration: connection.configuration.polling,
            sendCommand: { [weak connection] command in
                guard let connection else { return }
                try await connection.send(command)
            },
            isActive: { [weak connection] in
                await connection?.isAppActive() ?? false
            },
            pollScheduler: pollScheduler,
            pongStore: TydomPongStore(),
            cdataReplyStore: TydomCDataReplyStore(),
            log: log
        )

        return live(hydrator: hydrator, effectExecutor: effectExecutor)
    }
}
