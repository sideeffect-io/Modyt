import DeltaDoreClient

struct SceneExecutionStoreFactory: Sendable {
    private let makeStore: @MainActor @Sendable (String) -> SceneExecutionStore

    init(make: @escaping @MainActor @Sendable (String) -> SceneExecutionStore) {
        self.makeStore = make
    }

    @MainActor
    func make(uniqueId: String) -> SceneExecutionStore {
        makeStore(uniqueId)
    }

    static func live(dependencyBag: DependencyBag) -> Self {
        let gatewayClient = dependencyBag.gatewayClient
        let ackRepository = dependencyBag.localStorageDatasources.ackRepository
        let runtime = SceneExecutionRuntime(
            gatewayClient: gatewayClient,
            ackRepository: ackRepository
        )

        return Self { uniqueId in
            SceneExecutionStore(
                executeScene: .init(
                    executeScene: {
                        async let result = runtime.executeScene(sceneID: uniqueId)
                        try? await Task.sleep(for: .seconds(2))
                        return await result
                    }
                ),
                clearFeedback: .init(
                    clearFeedback: {
                        try? await Task.sleep(for: .seconds(2))
                    }
                )
            )
        }
    }
}

actor SceneExecutionRuntime {
    private let gatewayClient: DeltaDoreClient
    private let ackRepository: ACKRepository

    init(
        gatewayClient: DeltaDoreClient,
        ackRepository: ACKRepository
    ) {
        self.gatewayClient = gatewayClient
        self.ackRepository = ackRepository
    }

    func executeScene(sceneID: String) async -> SceneExecutionResult {
        guard Int(sceneID) != nil else {
            return .invalidSceneIdentifier
        }

        let transactionID = TydomCommand.defaultTransactionId()
        let command = TydomCommand.activateScenario(sceneID, transactionId: transactionID)

        do {
            try await gatewayClient.send(text: command.request)
        } catch {
            return .sendFailed
        }

        let ackMessage: ACKRepository.ACKMessage
        do {
            ackMessage = try await ackRepository.waitForACKMessage(
                transactionId: transactionID,
                timeout: .seconds(3)
            )
        } catch {
            return .sentWithoutAcknowledgement
        }

        guard let uriOrigin = ackMessage.metadata.uriOrigin,
              uriOrigin.hasPrefix("/scenarios/"),
              uriOrigin != "/scenarios/file" else {
            return .sentWithoutAcknowledgement
        }

        let statusCode = ackMessage.ack.statusCode
        if (200..<300).contains(statusCode) {
            return .acknowledged(statusCode: statusCode)
        }

        return .rejected(statusCode: statusCode)
    }
}
