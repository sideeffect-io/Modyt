import Foundation

extension TydomMessageEffectExecutor {
    static func live(
        pollingConfiguration: TydomConnection.Configuration.Polling = .init(),
        sendCommand: @escaping @Sendable (TydomCommand) async throws -> Void,
        isActive: @escaping @Sendable () async -> Bool = { true },
        pollScheduler: TydomMessagePollScheduler? = nil,
        pongStore: TydomPongStore = TydomPongStore(),
        cdataReplyStore: TydomCDataReplyStore = TydomCDataReplyStore(),
        log: @escaping @Sendable (String) -> Void = { _ in }
    ) -> TydomMessageEffectExecutor {
        let activeCheck: @Sendable () async -> Bool
        if pollingConfiguration.onlyWhenActive {
            activeCheck = isActive
        } else {
            activeCheck = { true }
        }
        let scheduler = pollScheduler ?? TydomMessagePollScheduler(
            send: sendCommand,
            isActive: activeCheck
        )
        let dependencies = Dependencies(
            sendCommand: sendCommand,
            pollScheduler: { urls, _ in
                let effectiveInterval = pollingConfiguration.intervalSeconds
                guard pollingConfiguration.isEnabled else {
                    log("Polling disabled (intervalSeconds=\(effectiveInterval)).")
                    return
                }
                if urls.isEmpty {
                    log("Polling schedule skipped (no urls).")
                    return
                }
                log("Polling scheduled for \(urls.count) url(s) every \(effectiveInterval)s.")
                await scheduler.schedule(urls: urls, intervalSeconds: effectiveInterval)
            },
            pollOnceScheduled: {
                log("Polling once for scheduled urls.")
                await scheduler.pollOnceScheduled()
            },
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
