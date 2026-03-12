struct TemperatureStoreFactory: Sendable {
    private let makeStore: @MainActor @Sendable (DeviceIdentifier) -> TemperatureStore

    init(make: @escaping @MainActor @Sendable (DeviceIdentifier) -> TemperatureStore) {
        self.makeStore = make
    }

    @MainActor
    func make(identifier: DeviceIdentifier) -> TemperatureStore {
        makeStore(identifier)
    }

    static func live(dependencyBag: DependencyBag) -> Self {
        let deviceRepository = dependencyBag.localStorageDatasources.deviceRepository

        return Self { identifier in
            TemperatureStore(
                observeTemperature: .init(
                    observeTemperature: {
                        await deviceRepository.observeByID(identifier)
                    }
                )
            )
        }
    }
}
