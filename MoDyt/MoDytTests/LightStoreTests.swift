import Testing
import DeltaDoreClient
@testable import MoDyt

@MainActor
struct LightStoreTests {
    @Test
    func setPowerUsesPowerKeyAndDispatchesOptimisticThenCommand() async {
        let recorder = TestRecorder<String>()
        let store = LightStore(
            uniqueId: "light-1",
            initialDevice: makeLightDevice(
                uniqueId: "light-1",
                data: ["on": .bool(false), "level": .number(35)],
                metadata: ["level": .object(["min": .number(0), "max": .number(100)])]
            ),
            dependencies: .init(
                observeLight: { _ in
                    AsyncStream { continuation in
                        continuation.finish()
                    }
                },
                applyOptimisticUpdate: { uniqueId, key, value in
                    await recorder.record("optimistic:\(uniqueId):\(key):\(value.boolValue == true)")
                },
                sendCommand: { uniqueId, key, value in
                    await recorder.record("command:\(uniqueId):\(key):\(value.boolValue == true)")
                }
            )
        )

        store.setPower(true)
        await settleAsyncState()

        #expect(store.descriptor.isOn)
        let entries = await recorder.values
        #expect(entries.contains("optimistic:light-1:on:true"))
        #expect(entries.contains("command:light-1:on:true"))
    }

    @Test
    func setPowerFallsBackToLevelWhenPowerKeyMissing() async {
        let recorder = TestRecorder<String>()
        let store = LightStore(
            uniqueId: "light-2",
            initialDevice: makeLightDevice(
                uniqueId: "light-2",
                data: ["level": .number(70)],
                metadata: ["level": .object(["min": .number(10), "max": .number(90)])]
            ),
            dependencies: .init(
                observeLight: { _ in
                    AsyncStream { continuation in
                        continuation.finish()
                    }
                },
                applyOptimisticUpdate: { uniqueId, key, value in
                    await recorder.record("optimistic:\(uniqueId):\(key):\(Int(value.numberValue ?? -1))")
                },
                sendCommand: { uniqueId, key, value in
                    await recorder.record("command:\(uniqueId):\(key):\(Int(value.numberValue ?? -1))")
                }
            )
        )

        store.setPower(false)
        await settleAsyncState()

        #expect(!store.descriptor.isOn)
        #expect(store.descriptor.level == 10)
        let entries = await recorder.values
        #expect(entries.contains("optimistic:light-2:level:10"))
        #expect(entries.contains("command:light-2:level:10"))
    }

    @Test
    func setPowerDoesNothingWhenValueIsUnchanged() async {
        let recorder = TestRecorder<String>()
        let store = LightStore(
            uniqueId: "light-3",
            initialDevice: makeLightDevice(
                uniqueId: "light-3",
                data: ["state": .bool(false)]
            ),
            dependencies: .init(
                observeLight: { _ in
                    AsyncStream { continuation in
                        continuation.finish()
                    }
                },
                applyOptimisticUpdate: { _, _, _ in
                    await recorder.record("optimistic")
                },
                sendCommand: { _, _, _ in
                    await recorder.record("command")
                }
            )
        )

        store.setPower(false)
        await settleAsyncState()

        #expect((await recorder.values).isEmpty)
    }

    @Test
    func setLevelNormalizedDispatchesLevelAndPowerWhenNeeded() async {
        let recorder = TestRecorder<String>()
        let store = LightStore(
            uniqueId: "light-5",
            initialDevice: makeLightDevice(
                uniqueId: "light-5",
                data: ["on": .bool(false), "level": .number(0)],
                metadata: ["level": .object(["min": .number(0), "max": .number(100)])]
            ),
            dependencies: .init(
                observeLight: { _ in
                    AsyncStream { continuation in
                        continuation.finish()
                    }
                },
                applyOptimisticUpdate: { uniqueId, key, value in
                    let number = value.numberValue.map { String(Int($0.rounded())) } ?? ""
                    let bool = value.boolValue.map { String($0) } ?? ""
                    await recorder.record("optimistic:\(uniqueId):\(key):\(number)\(bool)")
                },
                sendCommand: { uniqueId, key, value in
                    let number = value.numberValue.map { String(Int($0.rounded())) } ?? ""
                    let bool = value.boolValue.map { String($0) } ?? ""
                    await recorder.record("command:\(uniqueId):\(key):\(number)\(bool)")
                }
            )
        )

        store.setLevelNormalized(0.4)
        await settleAsyncState()

        #expect(store.descriptor.level >= 39 && store.descriptor.level <= 41)
        #expect(store.descriptor.isOn)

        let entries = await recorder.values
        #expect(entries.contains("optimistic:light-5:level:40"))
        #expect(entries.contains("command:light-5:level:40"))
        #expect(entries.contains("optimistic:light-5:on:true"))
        #expect(entries.contains("command:light-5:on:true"))
    }

    @Test
    func setLevelNormalizedWithoutLevelKeyFallsBackToPowerToggle() async {
        let recorder = TestRecorder<String>()
        let store = LightStore(
            uniqueId: "light-6",
            initialDevice: makeLightDevice(
                uniqueId: "light-6",
                data: ["on": .bool(false)]
            ),
            dependencies: .init(
                observeLight: { _ in
                    AsyncStream { continuation in
                        continuation.finish()
                    }
                },
                applyOptimisticUpdate: { _, key, value in
                    await recorder.record("optimistic:\(key):\(value.boolValue == true)")
                },
                sendCommand: { _, key, value in
                    await recorder.record("command:\(key):\(value.boolValue == true)")
                }
            )
        )

        store.setLevelNormalized(0.8)
        await settleAsyncState()

        #expect(store.descriptor.isOn)
        let entries = await recorder.values
        #expect(entries == ["optimistic:on:true", "command:on:true"])
    }

    @Test
    func observationUpdatesDescriptorFromIncomingDevice() async {
        let streamBox = BufferedStreamBox<DeviceRecord?>()
        let store = LightStore(
            uniqueId: "light-4",
            initialDevice: makeLightDevice(
                uniqueId: "light-4",
                data: ["on": .bool(false), "level": .number(10)]
            ),
            dependencies: .init(
                observeLight: { _ in streamBox.stream },
                applyOptimisticUpdate: { _, _, _ in },
                sendCommand: { _, _, _ in }
            )
        )

        streamBox.yield(
            makeLightDevice(
                uniqueId: "light-4",
                data: ["on": .bool(true), "level": .number(85)]
            )
        )
        await settleAsyncState()

        #expect(store.descriptor.isOn)
        #expect(store.descriptor.level == 85)
        #expect(store.descriptor.powerKey == "on")
        #expect(store.descriptor.levelKey == "level")
    }

    private func makeLightDevice(
        uniqueId: String,
        data: [String: JSONValue],
        metadata: [String: JSONValue]? = nil
    ) -> DeviceRecord {
        TestSupport.makeDevice(
            uniqueId: uniqueId,
            name: "Driveway",
            usage: "light",
            data: data,
            metadata: metadata
        )
    }
}
