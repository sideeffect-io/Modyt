import DeltaDoreClient

struct HeatPumpStoreFactory: Sendable {
    private let makeStore: @MainActor @Sendable (DeviceIdentifier) -> HeatPumpStore

    init(make: @escaping @MainActor @Sendable (DeviceIdentifier) -> HeatPumpStore) {
        self.makeStore = make
    }

    @MainActor
    func make(identifier: DeviceIdentifier) -> HeatPumpStore {
        makeStore(identifier)
    }

    static func live(dependencyBag: DependencyBag) -> Self {
        let deviceRepository = dependencyBag.localStorageDatasources.deviceRepository
        let ackRepository = dependencyBag.localStorageDatasources.ackRepository
        let gatewayClient = dependencyBag.gatewayClient

        return Self { identifier in
            HeatPumpStore(
                observeHeatPump: .init(
                    observeHeatPump: {
                        await deviceRepository
                            .observeByDeviceID(identifier.deviceId)
                            .map { devices in
                                HeatPumpStore.resolveObservedDevice(
                                    for: identifier,
                                    in: devices
                                )
                            }
                            .removeDuplicates()
                    }
                ),
                executeSetPoint: .init(
                    executeSetPointCommand: { command in
                        try? await gatewayClient.send(text: command.request)
                        _ = try? await ackRepository.waitForACK(transactionId: command.transactionId)
                    },
                    makeTransactionID: {
                        TydomCommand.defaultTransactionId()
                    }
                )
            )
        }
    }
}
