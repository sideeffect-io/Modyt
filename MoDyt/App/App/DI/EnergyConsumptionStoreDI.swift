struct EnergyConsumptionStoreFactory: Sendable {
    private let makeStore: @MainActor @Sendable (DeviceIdentifier) -> EnergyConsumptionStore

    init(make: @escaping @MainActor @Sendable (DeviceIdentifier) -> EnergyConsumptionStore) {
        self.makeStore = make
    }

    @MainActor
    func make(identifier: DeviceIdentifier) -> EnergyConsumptionStore {
        makeStore(identifier)
    }

    static func live(dependencyBag: DependencyBag) -> Self {
        let deviceRepository = dependencyBag.localStorageDatasources.deviceRepository

        return Self { identifier in
            EnergyConsumptionStore(
                observeEnergyConsumption: .init(
                    observeEnergyConsumption: {
                        await deviceRepository.observeByID(identifier)
                    }
                )
            )
        }
    }
}
