import Foundation
import SwiftUI
import DeltaDoreClient

struct SceneExecutionStoreFactory {
    let make: @MainActor (String) -> SceneExecutionStore

    static func live(dependencies: DependencyBag) -> SceneExecutionStoreFactory {
        let runtime = SceneExecutionRuntime(
            gatewayClient: dependencies.gatewayClient,
            ackRepository: dependencies.localStorageDatasources.ackRepository
        )

        return SceneExecutionStoreFactory { uniqueId in
            SceneExecutionStore(
                uniqueId: uniqueId,
                dependencies: .init(
                    executeScene: { sceneID in
                        await runtime.executeScene(sceneID: sceneID)
                    }
                )
            )
        }
    }
}

private actor SceneExecutionRuntime {
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

        let transactionID = TydomCommand.defaultTransactionId(now: Date.init)
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

private struct SceneExecutionStoreFactoryKey: EnvironmentKey {
    static var defaultValue: SceneExecutionStoreFactory {
        SceneExecutionStoreFactory.live(dependencies: .live())
    }
}

extension EnvironmentValues {
    var sceneExecutionStoreFactory: SceneExecutionStoreFactory {
        get { self[SceneExecutionStoreFactoryKey.self] }
        set { self[SceneExecutionStoreFactoryKey.self] = newValue }
    }
}
