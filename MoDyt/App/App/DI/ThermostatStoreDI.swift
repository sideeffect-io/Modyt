struct ThermostatStoreFactory: Sendable {
    private let makeStore: @MainActor @Sendable (DeviceIdentifier) -> ThermostatStore

    init(make: @escaping @MainActor @Sendable (DeviceIdentifier) -> ThermostatStore) {
        self.makeStore = make
    }

    @MainActor
    func make(identifier: DeviceIdentifier) -> ThermostatStore {
        makeStore(identifier)
    }

    static func live(dependencyBag: DependencyBag) -> Self {
        let deviceRepository = dependencyBag.localStorageDatasources.deviceRepository

        return Self { identifier in
            ThermostatStore(
                observeThermostat: .init(
                    observeThermostat: {
                        await deviceRepository.observeByID(identifier).removeDuplicates()
                    }
                )
            )
        }
    }
}
