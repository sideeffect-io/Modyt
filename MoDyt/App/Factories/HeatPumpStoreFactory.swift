import SwiftUI
import DeltaDoreClient

struct HeatPumpStoreFactory {
    let make: @MainActor (String) -> HeatPumpStore
    
    static func live(dependencies: DependencyBag) -> HeatPumpStoreFactory {
        let deviceRepository = dependencies.localStorageDatasources.deviceRepository
        let gatewayClient = dependencies.gatewayClient
        let ackRepository = dependencies.localStorageDatasources.ackRepository
        
        return HeatPumpStoreFactory { uniqueId in
            HeatPumpStore(
                uniqueId: uniqueId,
                dependencies: .init(
                    observeHeatPump: { await deviceRepository.observeByID($0) },
                    executeSetPointCommand: { command in
                        try? await gatewayClient.send(text: command.request)
                        _ = try? await ackRepository.waitForACK(transactionId: command.transactionId)
                    },
                    makeTransactionID: {
                        TydomCommand.defaultTransactionId(now: Date.init)
                    }
                )
            )
        }
    }
}

private struct HeatPumpStoreFactoryKey: EnvironmentKey {
    static var defaultValue: HeatPumpStoreFactory {
        HeatPumpStoreFactory.live(dependencies: .live())
    }
}

extension EnvironmentValues {
    var heatPumpStoreFactory: HeatPumpStoreFactory {
        get { self[HeatPumpStoreFactoryKey.self] }
        set { self[HeatPumpStoreFactoryKey.self] = newValue }
    }
}
