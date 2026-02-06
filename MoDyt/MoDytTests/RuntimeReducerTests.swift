import Testing
import DeltaDoreClient
@testable import MoDyt

struct RuntimeReducerTests {
    @Test
    func devicesUpdateDerivesGroupedAndFavorites() {
        let deviceA = TestSupport.makeDevice(
            uniqueId: "favorite-1",
            name: "Kitchen Light",
            usage: "light",
            isFavorite: true,
            dashboardOrder: 1,
            data: ["on": .bool(false)]
        )
        let deviceB = TestSupport.makeDevice(
            uniqueId: "favorite-0",
            name: "Living Light",
            usage: "light",
            isFavorite: true,
            dashboardOrder: 0,
            data: ["on": .bool(true)]
        )
        let shutter = TestSupport.makeDevice(
            uniqueId: "shutter-1",
            name: "Main Shutter",
            usage: "shutter",
            data: ["level": .number(0)]
        )

        let (nextState, effects) = RuntimeReducer.reduce(
            state: .initial,
            event: .devicesUpdated([deviceA, shutter, deviceB])
        )

        #expect(effects.isEmpty)
        #expect(nextState.groupedDevices.count == 2)
        #expect(nextState.favorites.map(\.uniqueId) == ["favorite-0", "favorite-1"])
    }

    @Test
    func shutterControlGeneratesOnlyCommand() {
        let shutter = TestSupport.makeDevice(
            uniqueId: "shutter-1",
            name: "Main Shutter",
            usage: "shutter",
            data: ["level": .number(0)],
            metadata: [
                "level": .object([
                    "min": .number(0),
                    "max": .number(100)
                ])
            ]
        )

        let (stateWithDevice, _) = RuntimeReducer.reduce(
            state: .initial,
            event: .devicesUpdated([shutter])
        )

        let (_, effects) = RuntimeReducer.reduce(
            state: stateWithDevice,
            event: .deviceControlChanged(uniqueId: "shutter-1", key: "level", value: .number(50))
        )

        #expect(effects == [.sendDeviceCommand(uniqueId: "shutter-1", key: "level", value: .number(50))])
    }

    @Test
    func nonShutterControlGeneratesOptimisticUpdateAndCommand() {
        let light = TestSupport.makeDevice(
            uniqueId: "light-1",
            name: "Desk Light",
            usage: "light",
            data: ["on": .bool(false)]
        )

        let (stateWithDevice, _) = RuntimeReducer.reduce(
            state: .initial,
            event: .devicesUpdated([light])
        )

        let (_, effects) = RuntimeReducer.reduce(
            state: stateWithDevice,
            event: .deviceControlChanged(uniqueId: "light-1", key: "on", value: .bool(true))
        )

        #expect(effects == [
            .applyOptimisticUpdate(uniqueId: "light-1", key: "on", value: .bool(true)),
            .sendDeviceCommand(uniqueId: "light-1", key: "on", value: .bool(true))
        ])
    }

    @Test
    func disconnectResetsStateAndRequestsDisconnectEffect() {
        let populated = RuntimeState(
            devices: [
                TestSupport.makeDevice(uniqueId: "d1", name: "Device", usage: "light", isFavorite: true, dashboardOrder: 0, data: ["on": .bool(true)])
            ],
            groupedDevices: [
                DeviceGroupSection(group: .light, devices: [
                    TestSupport.makeDevice(uniqueId: "d1", name: "Device", usage: "light", isFavorite: true, dashboardOrder: 0, data: ["on": .bool(true)])
                ])
            ],
            favorites: [
                TestSupport.makeDevice(uniqueId: "d1", name: "Device", usage: "light", isFavorite: true, dashboardOrder: 0, data: ["on": .bool(true)])
            ],
            isAppActive: true
        )

        let (nextState, effects) = RuntimeReducer.reduce(
            state: populated,
            event: .disconnectTapped
        )

        #expect(nextState.devices.isEmpty)
        #expect(nextState.groupedDevices.isEmpty)
        #expect(nextState.favorites.isEmpty)
        #expect(effects == [.disconnectAndClearStoredData])
    }

    @MainActor
    @Test
    func disconnectedEventEmitsDelegateEvent() {
        let store = RuntimeStore(
            environment: TestSupport.makeEnvironment(),
            connection: TestSupport.makeConnection()
        )
        var didEmit = false
        store.onDelegateEvent = { delegateEvent in
            if case .didDisconnect = delegateEvent {
                didEmit = true
            }
        }

        store.send(.disconnected)

        #expect(didEmit)
    }
}
