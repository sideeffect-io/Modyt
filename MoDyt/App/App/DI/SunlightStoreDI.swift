struct SunlightStoreFactory: Sendable {
    private let makeStore: @MainActor @Sendable (DeviceIdentifier) -> SunlightStore

    init(make: @escaping @MainActor @Sendable (DeviceIdentifier) -> SunlightStore) {
        self.makeStore = make
    }

    @MainActor
    func make(identifier: DeviceIdentifier) -> SunlightStore {
        makeStore(identifier)
    }

    static func live(dependencyBag: DependencyBag) -> Self {
        let deviceRepository = dependencyBag.localStorageDatasources.deviceRepository

        return Self { identifier in
            SunlightStore(
                observeSunlight: .init(
                    observeSunlight: {
                        await deviceRepository.observeByID(identifier)
                    }
                )
            )
        }
    }
}
