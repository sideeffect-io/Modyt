import DeltaDoreClient
import SwiftUI

enum SceneExecutionStoreDependencyFactory {
    static func make(
        dependencyBag: DependencyBag = .production
    ) -> SceneExecutionStore.Dependencies {
        let gatewayClient = dependencyBag.gatewayClient
        let ackRepository = dependencyBag.localStorageDatasources.ackRepository
        let runtime = SceneExecutionRuntime(
            gatewayClient: gatewayClient,
            ackRepository: ackRepository
        )

        return .init(
            executeScene: { sceneID in
                await runtime.executeScene(sceneID: sceneID)
            }
        )
    }
}

extension EnvironmentValues {
    @Entry var sceneExecutionStoreDependencies: SceneExecutionStore.Dependencies =
        SceneExecutionStoreDependencyFactory.make()
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
