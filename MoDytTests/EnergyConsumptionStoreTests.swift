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
    func energyDescriptorAggregatesDistributionBucketsBeforeCumulativeIndex() {
        let device = makeTestDevice(
            identifier: .init(deviceId: 33, endpointId: 1),
            usage: "conso",
            kind: "energy",
            data: [
                "energyDistrib_ELEC_HEATING": .number(15_509),
                "energyDistrib_ELEC_COOLING": .number(0),
                "energyDistrib_ELEC_HOTWATER": .number(213_185),
                "energyDistrib_ELEC_OUTLET": .number(27_852),
                "energyDistrib_ELEC_OTHER": .number(180_924),
                "energyIndex_ELEC_TOTAL": .number(66_288_359)
            ]
        )

        let descriptor = device.energyConsumptionDescriptor()

        #expect(descriptor?.key == "energyDistrib_TOTAL")
        #expect(abs((descriptor?.value ?? 0) - 437.47) < 0.001)
        #expect(descriptor?.unitSymbol == "kWh")
    }

    @Test
    func energyDescriptorPrefersKnownTotalKeysOverLexicographicBuckets() {
        let device = makeTestDevice(
            identifier: .init(deviceId: 34, endpointId: 1),
            usage: "conso",
            kind: "energy",
            data: [
                "energyDistrib_ELEC_COOLING": .number(0),
                "energyIndex_ELEC_TOTAL": .number(123.4)
            ]
        )

        let descriptor = device.energyConsumptionDescriptor()

        #expect(descriptor?.key == "energyIndex_ELEC_TOTAL")
        #expect(descriptor?.value == 123.4)
    }

    @Test
    func energyDescriptorReturnsNilForUnsupportedUsage() {
        let device = makeTestDevice(
            identifier: .init(deviceId: 35, endpointId: 1),
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
            observeEnergyConsumption: .init(
                observeEnergyConsumption: {
                    await observeCalls.increment()
                    return streamBox.stream
                }
            )
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
            observeEnergyConsumption: .init(
                observeEnergyConsumption: { streamBox.stream }
            )
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
