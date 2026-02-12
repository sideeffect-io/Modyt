import Foundation
import Testing
import DeltaDoreClient
@testable import MoDyt

@MainActor
struct SmokeStoreTests {
    @Test
    func initUsesInitialSmokeDescriptor() {
        let store = SmokeStore(
            uniqueId: "smoke-1",
            initialDevice: makeSmokeDevice(
                uniqueId: "smoke-1",
                smokeDetected: false,
                batteryDefect: false
            ),
            dependencies: .init(
                observeSmoke: { _ in
                    AsyncStream { continuation in
                        continuation.finish()
                    }
                }
            )
        )

        #expect(store.descriptor?.smokeDetected == false)
        #expect(store.descriptor?.batteryDefect == false)
        #expect(store.descriptor?.health == .ok)
    }

    @Test
    func observationUpdatesDescriptorFromIncomingDevice() async {
        let streamBox = BufferedStreamBox<DeviceRecord?>()
        let store = SmokeStore(
            uniqueId: "smoke-2",
            initialDevice: makeSmokeDevice(
                uniqueId: "smoke-2",
                smokeDetected: false,
                batteryDefect: false
            ),
            dependencies: .init(
                observeSmoke: { _ in streamBox.stream }
            )
        )

        streamBox.yield(makeSmokeDevice(uniqueId: "smoke-2", smokeDetected: true, batteryDefect: false))
        await settleAsyncState()

        #expect(store.descriptor?.smokeDetected == true)
        #expect(store.descriptor?.health == .notOk)
    }

    @Test
    func observationClearsDescriptorWhenDeviceDisappears() async {
        let streamBox = BufferedStreamBox<DeviceRecord?>()
        let store = SmokeStore(
            uniqueId: "smoke-3",
            initialDevice: makeSmokeDevice(
                uniqueId: "smoke-3",
                smokeDetected: false,
                batteryDefect: false
            ),
            dependencies: .init(
                observeSmoke: { _ in streamBox.stream }
            )
        )

        streamBox.yield(nil)
        await settleAsyncState()

        #expect(store.descriptor == nil)
    }

    private func makeSmokeDevice(
        uniqueId: String,
        smokeDetected: Bool,
        batteryDefect: Bool
    ) -> DeviceRecord {
        TestSupport.makeDevice(
            uniqueId: uniqueId,
            name: "Smoke Detector",
            usage: "sensorDFR",
            data: [
                "techSmokeDefect": .bool(smokeDetected),
                "battDefect": .bool(batteryDefect)
            ]
        )
    }
}
