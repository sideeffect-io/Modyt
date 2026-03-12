import Testing
@testable import MoDyt

struct SmokeDescriptorTests {
    @Test
    func smokeDescriptorUsesPreferredKeysAndNormalizesBatteryFields() {
        let device = makeTestDevice(
            identifier: .init(deviceId: 11, endpointId: 1),
            usage: "sensorDFR",
            kind: "smoke",
            data: [
                "techSmokeDefect": .string("on"),
                "battDefect": .string("yes"),
                "battLevel": .string("120"),
            ]
        )

        let descriptor = device.smokeStoreDescriptor()

        #expect(descriptor?.smokeKey == "techSmokeDefect")
        #expect(descriptor?.smokeDetected == true)
        #expect(descriptor?.batteryDefect == true)
        #expect(descriptor?.hasBatteryIssue == true)
        #expect(descriptor?.batteryStatus?.batteryLevelKey == "battLevel")
        #expect(descriptor?.batteryStatus?.batteryLevel == 120)
        #expect(descriptor?.normalizedBatteryLevel == 100)
    }

    @Test
    func smokeDescriptorFallsBackToLikelyKeys() {
        let device = makeTestDevice(
            identifier: .init(deviceId: 12, endpointId: 1),
            usage: "unknown",
            kind: "sensor",
            data: [
                "fireAlarmState": .string("off"),
                "batteryFault": .number(0),
                "batteryLevel": .string("42"),
            ]
        )

        let descriptor = device.smokeStoreDescriptor()

        #expect(descriptor?.smokeKey == "fireAlarmState")
        #expect(descriptor?.smokeDetected == false)
        #expect(descriptor?.batteryStatus?.batteryDefectKey == "batteryFault")
        #expect(descriptor?.batteryStatus?.batteryDefect == false)
        #expect(descriptor?.normalizedBatteryLevel == 42)
    }

    @Test
    func smokeDescriptorReturnsNilForUnsupportedUsage() {
        let device = makeTestDevice(
            identifier: .init(deviceId: 13, endpointId: 1),
            usage: "light",
            kind: "light",
            data: ["techSmokeDefect": .bool(true)]
        )

        #expect(device.smokeStoreDescriptor() == nil)
    }
}

@MainActor
struct SmokeStoreObservationTests {
    @Test
    func startIsIdempotentAndObservationUpdatesDescriptor() async {
        let streamBox = TestAsyncStreamBox<Device?>()
        let observeCalls = TestCounter()
        let identifier = DeviceIdentifier(deviceId: 21, endpointId: 1)
        let store = SmokeStore(
            observeSmoke: .init(
                observeSmoke: {
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
            usage: "sensorDFR",
            kind: "smoke",
            data: ["smokeDetected": .bool(true)]
        ))

        #expect(await testWaitUntil {
            store.descriptor?.smokeDetected == true
        })
    }

    @Test
    func observationClearsDescriptorWhenDeviceDisappears() async {
        let streamBox = TestAsyncStreamBox<Device?>()
        let identifier = DeviceIdentifier(deviceId: 22, endpointId: 1)
        let store = SmokeStore(
            observeSmoke: .init(
                observeSmoke: { streamBox.stream }
            )
        )

        store.start()
        streamBox.yield(makeTestDevice(
            identifier: identifier,
            usage: "sensorDFR",
            kind: "smoke",
            data: ["smokeDetected": .bool(true)]
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
