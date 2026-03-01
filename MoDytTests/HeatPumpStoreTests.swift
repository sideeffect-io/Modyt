import Foundation
import Testing
@testable import MoDyt

struct HeatPumpReducerTests {
    struct TransitionCase: Sendable {
        let initial: HeatPumpState
        let event: HeatPumpEvent
        let expected: HeatPumpState
        let expectedEffects: [HeatPumpEffect]
    }

    @Test(arguments: transitionCases)
    func reducerAppliesConfiguredTransition(_ transition: TransitionCase) {
        let (nextState, effects) = HeatPumpReducer.reduce(
            state: transition.initial,
            event: transition.event
        )

        #expect(nextState == transition.expected)
        #expect(effects == transition.expectedEffects)
    }

    @Test
    func reducerLeavesUnknownTransitionUntouched() {
        let initial = HeatPumpState.featureIsIdle(Self.values(0.0, 0.0))

        let (nextState, effects) = HeatPumpReducer.reduce(
            state: initial,
            event: .newSetPointWasReceived(21.0)
        )

        #expect(nextState == initial)
        #expect(effects.isEmpty)
    }

    private static let transitionCases: [TransitionCase] = [
        .init(
            initial: .featureIsIdle(values(0.0, 0.0)),
            event: .valuesWereReceivedFromGateway(temperature: 19.0, setPoint: 20.0),
            expected: .featureIsStarted(values(19.0, 20.0)),
            expectedEffects: []
        ),
        .init(
            initial: .featureIsStarted(values(19.0, 19.0)),
            event: .valuesWereReceivedFromGateway(temperature: 20.0, setPoint: 21.0),
            expected: .featureIsStarted(values(20.0, 21.0)),
            expectedEffects: []
        ),
        .init(
            initial: .featureIsStarted(values(20.0, 20.0)),
            event: .newSetPointWasReceived(20.5),
            expected: .setPointIsBeingSet(values(20.0, 20.5)),
            expectedEffects: [.updateSetPoint(20.5)]
        ),
        .init(
            initial: .setPointIsBeingSet(values(20.0, 20.5)),
            event: .valuesWereReceivedFromGateway(temperature: 21.0, setPoint: 22.0),
            expected: .setPointIsBeingSet(values(21.0, 22.0)),
            expectedEffects: []
        ),
        .init(
            initial: .setPointIsBeingSet(values(20.0, 20.5)),
            event: .newSetPointWasReceived(21.0),
            expected: .setPointIsBeingSet(values(20.0, 21.0)),
            expectedEffects: [.updateSetPoint(21.0)]
        ),
        .init(
            initial: .setPointIsBeingSet(values(20.0, 20.5)),
            event: .setPointWasConfirmed,
            expected: .featureIsStarted(values(20.0, 20.5)),
            expectedEffects: []
        )
    ]

    private static func values(_ temperature: Double, _ setPoint: Double) -> HeatPumpValues {
        HeatPumpValues(temperature: temperature, setPoint: setPoint)
    }
}

@MainActor
struct HeatPumpStoreEffectTests {
    @Test
    func observationReceivesGatewayValueAndStartsFeature() async {
        let streamBox = DeviceStreamBox()
        let store = HeatPumpStore(
            identifier: .init(deviceId: 1, endpointId: 1),
            dependencies: .init(
                observeHeatPump: { _ in streamBox.stream },
                executeSetPointCommand: { _ in }
            )
        )

        streamBox.yield(
            makeDevice(
                identifier: .init(deviceId: 1, endpointId: 1),
                data: [
                    "temperature": .number(18.0),
                    "setpoint": .number(18.5)
                ]
            )
        )

        let didObserve = await waitUntil {
            store.state == .featureIsStarted(HeatPumpValues(temperature: 18.0, setPoint: 18.5))
        }

        #expect(didObserve)
        #expect(store.temperature == 18.0)
        #expect(store.setPoint == 18.5)
    }

    @Test
    func updateSetPointEffectSendsSetPointWasConfirmedWhenDone() async {
        let streamBox = DeviceStreamBox()
        let commands = RecordedGatewayCommands()
        let store = HeatPumpStore(
            identifier: .init(deviceId: 42, endpointId: 1),
            dependencies: .init(
                observeHeatPump: { _ in streamBox.stream },
                executeSetPointCommand: { command in
                    await commands.record(command)
                },
                makeTransactionID: { "tx-1" },
                setPointDebounceInterval: .milliseconds(0)
            )
        )

        streamBox.yield(
            makeDevice(
                identifier: .init(deviceId: 42, endpointId: 1),
                data: [
                    "temperature": .number(20.0),
                    "setpoint": .number(20.0)
                ]
            )
        )

        let didObserve = await waitUntil {
            store.state == .featureIsStarted(HeatPumpValues(temperature: 20.0, setPoint: 20.0))
        }
        #expect(didObserve)

        store.send(.newSetPointWasReceived(20.5))

        #expect(store.state == .setPointIsBeingSet(HeatPumpValues(temperature: 20.0, setPoint: 20.5)))

        let didComplete = await waitUntil {
            store.state == .featureIsStarted(HeatPumpValues(temperature: 20.0, setPoint: 20.5))
        }

        #expect(didComplete)
        let sentCommands = await commands.values()
        #expect(sentCommands.count == 1)
        #expect(sentCommands[0].transactionId == "tx-1")
        #expect(sentCommands[0].request.contains("PUT /devices/42/endpoints/1/data HTTP/1.1"))
        #expect(sentCommands[0].request.contains("Transac-Id: tx-1"))
        #expect(sentCommands[0].request.contains("\"name\":\"setpoint\""))
        #expect(sentCommands[0].request.contains("\"value\":\"20.5\""))
    }

    @Test
    func rapidSetPointCommandsAreDebounced() async throws {
        let streamBox = DeviceStreamBox()
        let commands = RecordedGatewayCommands()
        let transactionIDs = TransactionIDSequence(ids: ["tx-1", "tx-2", "tx-3", "tx-4"])
        let store = HeatPumpStore(
            identifier: .init(deviceId: 42, endpointId: 1),
            dependencies: .init(
                observeHeatPump: { _ in streamBox.stream },
                executeSetPointCommand: { command in
                    await commands.record(command)
                },
                makeTransactionID: { await transactionIDs.next() },
                setPointDebounceInterval: .milliseconds(120)
            )
        )

        streamBox.yield(
            makeDevice(
                identifier: .init(deviceId: 42, endpointId: 1),
                data: [
                    "temperature": .number(20.0),
                    "setpoint": .number(20.0)
                ]
            )
        )

        let didObserve = await waitUntil {
            store.state == .featureIsStarted(HeatPumpValues(temperature: 20.0, setPoint: 20.0))
        }
        #expect(didObserve)

        store.send(.newSetPointWasReceived(20.5))
        #expect(store.state == .setPointIsBeingSet(HeatPumpValues(temperature: 20.0, setPoint: 20.5)))

        store.send(.newSetPointWasReceived(21.0))
        #expect(store.state == .setPointIsBeingSet(HeatPumpValues(temperature: 20.0, setPoint: 21.0)))

        store.send(.newSetPointWasReceived(21.5))
        #expect(store.state == .setPointIsBeingSet(HeatPumpValues(temperature: 20.0, setPoint: 21.5)))

        try await Task.sleep(for: .milliseconds(40))
        #expect(await commands.values().isEmpty)
        try await Task.sleep(for: .milliseconds(400))

        let didComplete = await waitUntil(cycles: 120) {
            store.state == .featureIsStarted(HeatPumpValues(temperature: 20.0, setPoint: 21.5))
        }
        #expect(didComplete)
        let sentCommands = await commands.values()
        #expect(sentCommands.map(\.transactionId) == ["tx-1"])
        #expect(sentCommands.allSatisfy { $0.request.contains("\"name\":\"setpoint\"") })
        #expect(sentCommands.allSatisfy { $0.request.contains("\"value\":\"21.5\"") })
    }

    private func makeDevice(
        identifier: DeviceIdentifier,
        data: [String: JSONValue]
    ) -> Device {
        Device(
            id: identifier,
            deviceId: identifier.deviceId,
            endpointId: identifier.endpointId,
            name: "Heat Pump",
            usage: "boiler",
            kind: "heater",
            data: data,
            metadata: nil,
            isFavorite: false,
            dashboardOrder: nil,
            updatedAt: Date()
        )
    }

    private func waitUntil(
        cycles: Int = 30,
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
}

private actor RecordedGatewayCommands {
    private var storage: [HeatPumpGatewayCommand] = []

    func record(_ command: HeatPumpGatewayCommand) {
        storage.append(command)
    }

    func values() -> [HeatPumpGatewayCommand] {
        storage
    }
}

private actor TransactionIDSequence {
    private var ids: [String]

    init(ids: [String]) {
        self.ids = ids
    }

    func next() -> String {
        if ids.isEmpty {
            return "tx-fallback"
        }
        return ids.removeFirst()
    }
}

private final class DeviceStreamBox: @unchecked Sendable {
    let stream: AsyncStream<Device?>

    private let continuation: AsyncStream<Device?>.Continuation

    init() {
        var localContinuation: AsyncStream<Device?>.Continuation?
        self.stream = AsyncStream { continuation in
            localContinuation = continuation
        }
        self.continuation = localContinuation!
    }

    func yield(_ value: Device?) {
        continuation.yield(value)
    }
}
