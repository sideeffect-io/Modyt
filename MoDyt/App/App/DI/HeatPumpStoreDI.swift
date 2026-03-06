import SwiftUI
import DeltaDoreClient

enum HeatPumpStoreDependencyFactory {
    static func make(
        dependencyBag: DependencyBag = .production
    ) -> HeatPumpStore.Dependencies {
        let deviceRepository = dependencyBag.localStorageDatasources.deviceRepository
        let ackRepository = dependencyBag.localStorageDatasources.ackRepository
        let gatewayClient = dependencyBag.gatewayClient

        return .init(
            observeHeatPump: { requestedIdentifier in
                await deviceRepository
                    .observeByDeviceID(requestedIdentifier.deviceId)
                    .map { devices in
                        HeatPumpStore.resolveObservedDevice(
                            for: requestedIdentifier,
                            in: devices
                        )
                    }
                    .removeDuplicates()
            },
            executeSetPointCommand: { command in
                try? await gatewayClient.send(text: command.request)
                _ = try? await ackRepository.waitForACK(transactionId: command.transactionId)
            },
            makeTransactionID: {
                TydomCommand.defaultTransactionId()
            }
        )
    }
}

extension EnvironmentValues {
    @Entry var heatPumpStoreDependencies: HeatPumpStore.Dependencies =
        HeatPumpStoreDependencyFactory.make()
}
