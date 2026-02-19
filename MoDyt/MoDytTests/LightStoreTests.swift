import Foundation
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
                applyOptimisticChanges: { uniqueId, changes in
                    for key in changes.keys.sorted() {
                        guard let value = changes[key] else { continue }
                        await recorder.record("optimistic:\(uniqueId):\(key):\(value.boolValue == true)")
                    }
                },
                sendCommand: { uniqueId, key, value in
                    await recorder.record("command:\(uniqueId):\(key):\(value.boolValue == true)")
                }
            )
        )

        store.setPower(true)
        let didDispatch = await waitUntil {
            let entries = await recorder.values
            return entries.contains("command:light-1:on:true")
        }

        #expect(store.descriptor.isOn)
        #expect(didDispatch)
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
                applyOptimisticChanges: { uniqueId, changes in
                    for key in changes.keys.sorted() {
                        guard let value = changes[key] else { continue }
                        await recorder.record("optimistic:\(uniqueId):\(key):\(Int(value.numberValue ?? -1))")
                    }
                },
                sendCommand: { uniqueId, key, value in
                    await recorder.record("command:\(uniqueId):\(key):\(Int(value.numberValue ?? -1))")
                }
            )
        )

        store.setPower(false)
        let didDispatch = await waitUntil {
            let entries = await recorder.values
            return entries.contains("command:light-2:level:10")
        }

        #expect(!store.descriptor.isOn)
        #expect(store.descriptor.level == 10)
        #expect(didDispatch)
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
                applyOptimisticChanges: { _, _ in
                    await recorder.record("optimistic")
                },
                sendCommand: { _, _, _ in
                    await recorder.record("command")
                }
            )
        )

        store.setPower(false)
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
                applyOptimisticChanges: { uniqueId, changes in
                    await recorder.record("optimisticBatch:\(uniqueId):\(changes.count)")
                    for key in changes.keys.sorted() {
                        guard let value = changes[key] else { continue }
                        let number = value.numberValue.map { String(Int($0.rounded())) } ?? ""
                        let bool = value.boolValue.map { String($0) } ?? ""
                        await recorder.record("optimistic:\(uniqueId):\(key):\(number)\(bool)")
                    }
                },
                sendCommand: { uniqueId, key, value in
                    let number = value.numberValue.map { String(Int($0.rounded())) } ?? ""
                    let bool = value.boolValue.map { String($0) } ?? ""
                    await recorder.record("command:\(uniqueId):\(key):\(number)\(bool)")
                }
            )
        )

        store.setLevelNormalized(0.4)
        let didDispatch = await waitUntil {
            let entries = await recorder.values
            return entries.contains("command:light-5:level:40")
                && entries.contains("command:light-5:on:true")
        }

        #expect(store.descriptor.level >= 39 && store.descriptor.level <= 41)
        #expect(store.descriptor.isOn)
        #expect(didDispatch)

        let entries = await recorder.values
        #expect(entries.filter { $0.hasPrefix("optimisticBatch:light-5") }.count == 1)
        #expect(entries.contains("optimisticBatch:light-5:2"))
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
                applyOptimisticChanges: { _, changes in
                    for key in changes.keys.sorted() {
                        guard let value = changes[key] else { continue }
                        await recorder.record("optimistic:\(key):\(value.boolValue == true)")
                    }
                },
                sendCommand: { _, key, value in
                    await recorder.record("command:\(key):\(value.boolValue == true)")
                }
            )
        )

        store.setLevelNormalized(0.8)
        let didDispatch = await waitUntil {
            (await recorder.values).count == 2
        }

        #expect(store.descriptor.isOn)
        #expect(didDispatch)
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
                applyOptimisticChanges: { _, _ in },
                sendCommand: { _, _, _ in }
            )
        )

        streamBox.yield(
            makeLightDevice(
                uniqueId: "light-4",
                data: ["on": .bool(true), "level": .number(85)]
            )
        )
        let didObserveRealtime = await waitUntil {
            store.descriptor.isOn && store.descriptor.level == 85
        }

        #expect(didObserveRealtime)
        #expect(store.descriptor.isOn)
        #expect(store.descriptor.level == 85)
        #expect(store.descriptor.powerKey == "on")
        #expect(store.descriptor.levelKey == "level")
    }

    @Test
    func pendingStateSuppressesStaleEchoBeforeTimeout() async {
        let streamBox = BufferedStreamBox<DeviceRecord?>()
        let now = Date(timeIntervalSince1970: 5_000)
        let store = LightStore(
            uniqueId: "light-7",
            initialDevice: makeLightDevice(
                uniqueId: "light-7",
                data: ["on": .bool(false), "level": .number(0)],
                metadata: ["level": .object(["min": .number(0), "max": .number(100)])]
            ),
            dependencies: .init(
                observeLight: { _ in streamBox.stream },
                applyOptimisticChanges: { _, _ in },
                sendCommand: { _, _, _ in },
                now: { now }
            )
        )

        store.setLevelNormalized(1.0)
        let didApplyOptimistic = await waitUntil {
            store.descriptor.isOn && store.descriptor.level == 100
        }
        #expect(didApplyOptimistic)
        #expect(store.descriptor.isOn)
        #expect(store.descriptor.level == 100)

        streamBox.yield(
            makeLightDevice(
                uniqueId: "light-7",
                data: ["on": .bool(false), "level": .number(0)],
                metadata: ["level": .object(["min": .number(0), "max": .number(100)])]
            )
        )
        let remainedSuppressed = await waitUntil {
            store.descriptor.isOn && store.descriptor.level == 100
        }

        #expect(remainedSuppressed)
        #expect(store.descriptor.isOn)
        #expect(store.descriptor.level == 100)
    }

    @Test
    func pendingStateExpiresAndAcceptsIncomingDescriptor() async {
        let streamBox = BufferedStreamBox<DeviceRecord?>()
        var now = Date(timeIntervalSince1970: 6_000)
        let store = LightStore(
            uniqueId: "light-8",
            initialDevice: makeLightDevice(
                uniqueId: "light-8",
                data: ["on": .bool(false), "level": .number(0)],
                metadata: ["level": .object(["min": .number(0), "max": .number(100)])]
            ),
            dependencies: .init(
                observeLight: { _ in streamBox.stream },
                applyOptimisticChanges: { _, _ in },
                sendCommand: { _, _, _ in },
                now: { now }
            )
        )

        store.setLevelNormalized(1.0)
        let didApplyOptimistic = await waitUntil {
            store.descriptor.isOn
        }
        #expect(didApplyOptimistic)
        #expect(store.descriptor.isOn)

        now = now.addingTimeInterval(1.1)
        streamBox.yield(
            makeLightDevice(
                uniqueId: "light-8",
                data: ["on": .bool(false), "level": .number(0)],
                metadata: ["level": .object(["min": .number(0), "max": .number(100)])]
            )
        )
        let didReconcile = await waitUntil {
            !store.descriptor.isOn && store.descriptor.level == 0
        }

        #expect(didReconcile)
        #expect(!store.descriptor.isOn)
        #expect(store.descriptor.level == 0)
    }

    @Test
    func timeoutReconcilesSuppressedRealtimeDescriptorWithoutNewEvent() async {
        let streamBox = BufferedStreamBox<DeviceRecord?>()
        var now = Date(timeIntervalSince1970: 7_000)

        let store = LightStore(
            uniqueId: "light-9",
            initialDevice: makeLightDevice(
                uniqueId: "light-9",
                data: ["on": .bool(false), "level": .number(0)],
                metadata: ["level": .object(["min": .number(0), "max": .number(100)])]
            ),
            dependencies: .init(
                observeLight: { _ in streamBox.stream },
                applyOptimisticChanges: { _, _ in },
                sendCommand: { _, _, _ in },
                now: { now },
                pendingEchoSuppressionWindow: 0.03
            )
        )

        store.setLevelNormalized(1.0)
        let didApplyOptimistic = await waitUntil {
            store.descriptor.isOn && store.descriptor.level == 100
        }
        #expect(didApplyOptimistic)
        #expect(store.descriptor.isOn)
        #expect(store.descriptor.level == 100)

        streamBox.yield(
            makeLightDevice(
                uniqueId: "light-9",
                data: ["on": .bool(false), "level": .number(0)],
                metadata: ["level": .object(["min": .number(0), "max": .number(100)])]
            )
        )
        let remainedSuppressed = await waitUntil {
            store.descriptor.isOn
        }
        #expect(remainedSuppressed)
        #expect(store.descriptor.isOn)

        now = now.addingTimeInterval(1)
        let didReconcile = await waitUntil {
            !store.descriptor.isOn && store.descriptor.level == 0
        }

        #expect(didReconcile)
        #expect(!store.descriptor.isOn)
        #expect(store.descriptor.level == 0)
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
