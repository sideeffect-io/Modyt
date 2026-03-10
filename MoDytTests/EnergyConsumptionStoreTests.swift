import Testing
@testable import MoDyt

struct EnergyConsumptionDescriptorTests {
    @Test
    func energyDescriptorUsesPreferredKeyAndDefaultRange() {
        let device = makeTestDevice(
            identifier: .init(deviceId: 31, endpointId: 1),
            usage: "conso",
            kind: "energy",
            data: ["energyIndex_ELEC": .number(120.5)]
        )

        let descriptor = device.energyConsumptionDescriptor()

        #expect(descriptor?.key == "energyIndex_ELEC")
        #expect(descriptor?.value == 120.5)
        #expect(descriptor?.range == 0...864)
        #expect(descriptor?.unitSymbol == "kWh")
        #expect(descriptor?.clampedValue == 120.5)
        #expect(descriptor?.normalizedValue == (120.5 / 864))
    }

    @Test
    func energyDescriptorFallsBackToLikelyKeysConvertsWhAndClamps() {
        let device = makeTestDevice(
            identifier: .init(deviceId: 32, endpointId: 1),
            usage: "unknown",
            kind: "energy",
            data: [
                "dailyConsumption": .string("900000"),
                "dailyConsumptionUnit": .string("Wh"),
            ]
        )

        let descriptor = device.energyConsumptionDescriptor()

        #expect(descriptor?.key == "dailyConsumption")
        #expect(descriptor?.value == 900)
        #expect(descriptor?.unitSymbol == "kWh")
        #expect(descriptor?.clampedValue == 864)
        #expect(descriptor?.normalizedValue == 1)
    }

    @Test
    func energyDescriptorReturnsNilForUnsupportedUsage() {
        let device = makeTestDevice(
            identifier: .init(deviceId: 33, endpointId: 1),
            usage: "light",
            kind: "light",
            data: ["energyIndex": .number(20)]
        )

        #expect(device.energyConsumptionDescriptor() == nil)
    }
}

@MainActor
struct EnergyConsumptionStoreObservationTests {
    @Test
    func startIsIdempotentAndObservationUpdatesDescriptor() async {
        let streamBox = TestAsyncStreamBox<Device?>()
        let observeCalls = TestCounter()
        let identifier = DeviceIdentifier(deviceId: 41, endpointId: 1)
        let store = EnergyConsumptionStore(
            dependencies: .init(
                observeEnergyConsumption: { _ in
                    await observeCalls.increment()
                    return streamBox.stream
                }
            ),
            identifier: identifier
        )

        store.start()
        store.start()

        #expect(await testWaitUntilAsync {
            await observeCalls.value() == 1
        })

        streamBox.yield(makeTestDevice(
            identifier: identifier,
            usage: "conso",
            kind: "energy",
            data: ["energyIndex": .number(12)]
        ))

        #expect(await testWaitUntil {
            store.descriptor?.value == 12
        })
    }

    @Test
    func observationClearsDescriptorWhenDeviceDisappears() async {
        let streamBox = TestAsyncStreamBox<Device?>()
        let identifier = DeviceIdentifier(deviceId: 42, endpointId: 1)
        let store = EnergyConsumptionStore(
            dependencies: .init(
                observeEnergyConsumption: { _ in streamBox.stream }
            ),
            identifier: identifier
        )

        store.start()
        streamBox.yield(makeTestDevice(
            identifier: identifier,
            usage: "conso",
            kind: "energy",
            data: ["energyIndex": .number(14)]
        ))

        #expect(await testWaitUntil {
            store.descriptor != nil
        })

        streamBox.yield(nil)

        #expect(await testWaitUntil {
            store.descriptor == nil
        })
    }
}
