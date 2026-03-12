struct SmokeStoreFactory: Sendable {
    private let makeStore: @MainActor @Sendable (DeviceIdentifier) -> SmokeStore

    init(make: @escaping @MainActor @Sendable (DeviceIdentifier) -> SmokeStore) {
        self.makeStore = make
    }

    @MainActor
    func make(identifier: DeviceIdentifier) -> SmokeStore {
        makeStore(identifier)
    }

    static func live(dependencyBag: DependencyBag) -> Self {
        let deviceRepository = dependencyBag.localStorageDatasources.deviceRepository

        return Self { identifier in
            SmokeStore(
                observeSmoke: .init(
                    observeSmoke: {
                        await deviceRepository.observeByID(identifier).removeDuplicates()
                    }
                )
            )
        }
    }
}
