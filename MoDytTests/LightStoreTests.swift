import Testing
@testable import MoDyt

@MainActor
struct LightStoreTests {
    @Test
    func storeKeepsItsIdentifier() {
        let identifier = DeviceIdentifier(deviceId: 10, endpointId: 1)
        let store = LightStore(
            identifier: identifier,
            dependencies: .init()
        )

        #expect(store.identifier == identifier)
    }

    @Test
    func startIsANoOp() {
        let store = LightStore(
            identifier: DeviceIdentifier(deviceId: 10, endpointId: 1),
            dependencies: .init()
        )

        store.start()
    }
}
