import Foundation
import Testing
@testable import MoDyt

struct ShutterPositionMapperTests {
    @Test
    func gaugePositionInvertsRawPosition() {
        #expect(ShutterPositionMapper.gaugePosition(from: 100) == 0)
        #expect(ShutterPositionMapper.gaugePosition(from: 75) == 25)
        #expect(ShutterPositionMapper.gaugePosition(from: 25) == 75)
        #expect(ShutterPositionMapper.gaugePosition(from: 0) == 100)
    }

    @Test
    func gaugePositionClampsValuesToPercentRange() {
        #expect(ShutterPositionMapper.gaugePosition(from: -2) == 100)
        #expect(ShutterPositionMapper.gaugePosition(from: 123) == 0)
    }
}

struct DeviceShutterPositionTests {
    @Test
    func shutterDescriptorPrefersPositionSignalOverLevel() {
        let device = Device(
            id: .init(deviceId: 10, endpointId: 1),
            deviceId: 10,
            endpointId: 1,
            name: "Shutter",
            usage: "shutter",
            kind: "shutter",
            data: [
                "position": .number(30),
                "level": .number(90),
            ],
            metadata: nil,
            isFavorite: false,
            dashboardOrder: nil,
            shutterTargetPosition: nil,
            updatedAt: Date()
        )

        #expect(device.shutterControlDescriptor()?.key == "position")
        #expect(device.shutterPosition == 30)
    }
}

struct ShutterReducerTests {
    struct TransitionCase: Sendable {
        let initial: ShutterState
        let event: ShutterEvent
        let expected: ShutterState
        let expectedEffects: [ShutterEffect]
    }

    @Test(arguments: transitionCases)
    func reducerAppliesConfiguredTransition(_ transition: TransitionCase) {
        let (nextState, effects) = ShutterReducer.reduce(
            state: transition.initial,
            event: transition.event
        )

        #expect(nextState == transition.expected)
        #expect(effects == transition.expectedEffects)
    }

    @Test
    func reducerLeavesUnknownTransitionUntouched() {
        let initial = ShutterState.featureIsStarted(
            deviceIds: Self.deviceIds,
            position: 42,
            target: nil
        )

        let (nextState, effects) = ShutterReducer.reduce(
            state: initial,
            event: .timeoutHasExpired
        )

        #expect(nextState == initial)
        #expect(effects.isEmpty)
    }

    private static let deviceIds: [DeviceIdentifier] = [
        .init(deviceId: 10, endpointId: 1),
        .init(deviceId: 11, endpointId: 1),
    ]

    private static let transitionCases: [TransitionCase] = [
        .init(
            initial: .featureIsIdle(deviceIds: deviceIds, position: 0, target: nil),
            event: .valueWasReceived(position: 35, target: nil),
            expected: .featureIsStarted(deviceIds: deviceIds, position: 35, target: nil),
            expectedEffects: []
        ),
        .init(
            initial: .featureIsStarted(deviceIds: deviceIds, position: 20, target: nil),
            event: .valueWasReceived(position: 60, target: nil),
            expected: .featureIsStarted(deviceIds: deviceIds, position: 60, target: nil),
            expectedEffects: []
        ),
        .init(
            initial: .featureIsStarted(deviceIds: deviceIds, position: 30, target: nil),
            event: .targetWasSetInApp(target: 75),
            expected: .shutterIsMovingInApp(deviceIds: deviceIds, position: 30, target: 75),
            expectedEffects: [
                .sendCommand(deviceIds: deviceIds, position: 75),
                .startTimeout,
                .setTarget(deviceIds: deviceIds, target: 75),
            ]
        ),
        .init(
            initial: .featureIsStarted(deviceIds: deviceIds, position: 10, target: nil),
            event: .valueWasReceived(position: 20, target: 55),
            expected: .shutterIsMovingInApp(deviceIds: deviceIds, position: 20, target: 55),
            expectedEffects: [
                .startTimeout
            ]
        ),
        .init(
            initial: .shutterIsMovingInApp(deviceIds: deviceIds, position: 40, target: 60),
            event: .valueWasReceived(position: 45, target: 20),
            expected: .shutterIsMovingInApp(deviceIds: deviceIds, position: 45, target: 20),
            expectedEffects: [.startTimeout]
        ),
        .init(
            initial: .shutterIsMovingInApp(deviceIds: deviceIds, position: 20, target: 40),
            event: .valueWasReceived(position: 40, target: nil),
            expected: .shutterIsMovingInApp(
                deviceIds: deviceIds,
                position: 20,
                target: 40,
                hasTargetBeenACKed: true
            ),
            expectedEffects: []
        ),
        .init(
            initial: .shutterIsMovingInApp(deviceIds: deviceIds, position: 0, target: 100),
            event: .valueWasReceived(position: 100, target: nil),
            expected: .shutterIsMovingInApp(
                deviceIds: deviceIds,
                position: 0,
                target: 100,
                hasTargetBeenACKed: true
            ),
            expectedEffects: []
        ),
        .init(
            initial: .shutterIsMovingInApp(deviceIds: deviceIds, position: 70, target: 80),
            event: .timeoutHasExpired,
            expected: .featureIsStarted(deviceIds: deviceIds, position: 70, target: nil),
            expectedEffects: [
                .setTarget(deviceIds: deviceIds, target: nil)
            ]
        ),
    ]
}

@MainActor
struct ShutterStoreEffectTests {
    private let id10 = DeviceIdentifier(deviceId: 10, endpointId: 1)
    private let id11 = DeviceIdentifier(deviceId: 11, endpointId: 1)

    @Test
    func observationKeepsGatewayPositionInStore() async {
        let streamBox = DeviceArrayStreamBox()

        let store = ShutterStore(
            deviceIds: [id10],
            dependencies: .init(
                observeDevices: { _ in streamBox.stream },
                sendCommand: { _, _ in },
                sleep: {},
                setTarget: { _, _ in }
            )
        )

        streamBox.yield([
            makeShutter(identifier: id10, position: 25, target: nil),
        ])

        let didObserve = await waitUntil {
            store.state == .featureIsStarted(
                deviceIds: [id10],
                position: 25,
                target: nil
            )
        }

        #expect(didObserve)
    }

    @Test
    func observationKeepsRawPositionEvenWithNonPercentMetadataRange() async {
        let streamBox = DeviceArrayStreamBox()

        let store = ShutterStore(
            deviceIds: [id10],
            dependencies: .init(
                observeDevices: { _ in streamBox.stream },
                sendCommand: { _, _ in },
                sleep: {},
                setTarget: { _, _ in }
            )
        )

        streamBox.yield([
            Device(
                id: id10,
                deviceId: id10.deviceId,
                endpointId: 1,
                name: "Shutter \(id10.deviceId):\(id10.endpointId)",
                usage: "shutter",
                kind: "shutter",
                data: ["position": .number(0.2)],
                metadata: ["position": .object(["min": .number(0), "max": .number(1)])],
                isFavorite: false,
                dashboardOrder: nil,
                shutterTargetPosition: nil,
                updatedAt: Date()
            ),
        ])

        let didObserve = await waitUntil {
            store.state == .featureIsStarted(
                deviceIds: [id10],
                position: 0,
                target: nil
            )
        }

        #expect(didObserve)
    }

    @Test
    func observationAveragesMultiShutterValues() async {
        let streamBox = DeviceArrayStreamBox()
        let commands = RecordedShutterCommands()
        let targets = RecordedShutterTargets()
        let timeoutCounter = ThreadSafeCounter()

        let store = ShutterStore(
            deviceIds: [id10, id11],
            dependencies: .init(
                observeDevices: { _ in streamBox.stream },
                sendCommand: { deviceIds, position in
                    await commands.record(deviceIds: deviceIds, position: position)
                },
                sleep: {
                    timeoutCounter.increment()
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                },
                setTarget: { deviceIds, target in
                    await targets.record(deviceIds: deviceIds, target: target)
                }
            )
        )

        streamBox.yield([
            makeShutter(identifier: id10, position: 100, target: nil),
            makeShutter(identifier: id11, position: 0, target: 40),
        ])

        let didObserve = await waitUntil {
            store.state == .featureIsStarted(
                deviceIds: [id10, id11],
                position: 50,
                target: 40
            )
        }

        #expect(didObserve)
        #expect(await commands.values().isEmpty)
        #expect(await targets.values().isEmpty)
        #expect(timeoutCounter.value() == 0)
    }

    @Test
    func targetWasSetInAppSendsCommandStartsTimeoutAndPersistsTarget() async {
        let streamBox = DeviceArrayStreamBox()
        let commands = RecordedShutterCommands()
        let targets = RecordedShutterTargets()
        let timeoutCounter = ThreadSafeCounter()

        let store = ShutterStore(
            deviceIds: [id10, id11],
            dependencies: .init(
                observeDevices: { _ in streamBox.stream },
                sendCommand: { deviceIds, position in
                    await commands.record(deviceIds: deviceIds, position: position)
                },
                sleep: {
                    timeoutCounter.increment()
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                },
                setTarget: { deviceIds, target in
                    await targets.record(deviceIds: deviceIds, target: target)
                }
            )
        )

        streamBox.yield([
            makeShutter(identifier: id10, position: 20, target: nil),
            makeShutter(identifier: id11, position: 40, target: nil),
        ])

        let didStart = await waitUntil {
            store.state == .featureIsStarted(
                deviceIds: [id10, id11],
                position: 30,
                target: nil
            )
        }
        #expect(didStart)

        store.send(.targetWasSetInApp(target: 75))

        let didEmitEffects = await waitUntilAsync {
            let sentCommands = await commands.values()
            let persistedTargets = await targets.values()
            return sentCommands.count == 1 && persistedTargets.count == 1
        }
        #expect(didEmitEffects)

        #expect(
            store.state == .shutterIsMovingInApp(
                deviceIds: [id10, id11],
                position: 30,
                target: 75
            )
        )
        #expect(timeoutCounter.value() == 1)

        let sentCommands = await commands.values()
        #expect(sentCommands == [
            .init(deviceIds: [id10, id11], position: 75)
        ])

        let persistedTargets = await targets.values()
        #expect(persistedTargets == [
            .init(deviceIds: [id10, id11], target: 75)
        ])
    }

    private func makeShutter(
        identifier: DeviceIdentifier,
        position: Int,
        target: Int?
    ) -> Device {
        Device(
            id: identifier,
            deviceId: identifier.deviceId,
            endpointId: identifier.endpointId,
            name: "Shutter \(identifier.deviceId):\(identifier.endpointId)",
            usage: "shutter",
            kind: "shutter",
            data: ["position": .number(Double(position))],
            metadata: nil,
            isFavorite: false,
            dashboardOrder: nil,
            shutterTargetPosition: target,
            updatedAt: Date()
        )
    }

    private func waitUntil(
        cycles: Int = 60,
        condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        for _ in 0..<cycles {
            if condition() {
                return true
            }
            await Task.yield()
        }
        return condition()
    }

    private func waitUntilAsync(
        cycles: Int = 60,
        condition: @escaping @Sendable () async -> Bool
    ) async -> Bool {
        for _ in 0..<cycles {
            if await condition() {
                return true
            }
            await Task.yield()
        }
        return await condition()
    }
}

private final class DeviceArrayStreamBox: @unchecked Sendable {
    let stream: AsyncStream<[Device]>
    private let continuation: AsyncStream<[Device]>.Continuation

    init() {
        var localContinuation: AsyncStream<[Device]>.Continuation?
        self.stream = AsyncStream { continuation in
            localContinuation = continuation
        }
        self.continuation = localContinuation!
    }

    func yield(_ values: [Device]) {
        continuation.yield(values)
    }
}

private actor RecordedShutterCommands {
    struct Entry: Sendable, Equatable {
        let deviceIds: [DeviceIdentifier]
        let position: Int
    }

    private var entries: [Entry] = []

    func record(deviceIds: [DeviceIdentifier], position: Int) {
        entries.append(.init(deviceIds: deviceIds, position: position))
    }

    func values() -> [Entry] {
        entries
    }
}

private actor RecordedShutterTargets {
    struct Entry: Sendable, Equatable {
        let deviceIds: [DeviceIdentifier]
        let target: Int?
    }

    private var entries: [Entry] = []

    func record(deviceIds: [DeviceIdentifier], target: Int?) {
        entries.append(.init(deviceIds: deviceIds, target: target))
    }

    func values() -> [Entry] {
        entries
    }
}

private final class ThreadSafeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Int = 0

    func increment() {
        lock.lock()
        storage += 1
        lock.unlock()
    }

    func value() -> Int {
        lock.lock()
        let current = storage
        lock.unlock()
        return current
    }
}
