import Foundation
import Observation
import DeltaDoreClient
import Regulate

struct HeatPumpValues: Sendable, Equatable {
    let temperature: Double
    let setPoint: Double
    let unitSymbol: String

    init(
        temperature: Double,
        setPoint: Double,
        unitSymbol: String = "°C"
    ) {
        self.temperature = temperature
        self.setPoint = setPoint
        self.unitSymbol = unitSymbol
    }
}

enum HeatPumpState: Sendable, Equatable {
    case featureIsIdle(HeatPumpValues)
    case featureIsStarted(HeatPumpValues)
    case setPointIsBeingSet(HeatPumpValues)

    var values: HeatPumpValues {
        switch self {
        case .featureIsIdle(let values),
             .featureIsStarted(let values),
             .setPointIsBeingSet(let values):
            values
        }
    }
}

enum HeatPumpEvent: Sendable, Equatable {
    case valuesWereReceivedFromGateway(temperature: Double, setPoint: Double)
    case setPointWasConfirmed
    case newSetPointWasReceived(Double)
}

enum HeatPumpEffect: Sendable, Equatable {
    case updateSetPoint(Double)
}

struct HeatPumpGatewayCommand: Sendable, Equatable {
    let request: String
    let transactionId: String
}

@Observable
@MainActor
final class HeatPumpStore: StartableStore {
    struct StateMachine {
        static func reduce(
            _ state: HeatPumpState,
            _ event: HeatPumpEvent
        ) -> Transition<HeatPumpState, HeatPumpEffect> {
            var state = state

            switch (state, event) {
            case (.featureIsIdle(let values), .valuesWereReceivedFromGateway(let temperature, let setPoint)):
                let nextValues = HeatPumpValues(
                    temperature: temperature,
                    setPoint: setPoint,
                    unitSymbol: values.unitSymbol
                )
                state = .featureIsStarted(nextValues)
                return .init(state: state)

            case (.featureIsStarted(let values), .valuesWereReceivedFromGateway(let temperature, let setPoint)):
                let nextValues = HeatPumpValues(
                    temperature: temperature,
                    setPoint: setPoint,
                    unitSymbol: values.unitSymbol
                )
                state = .featureIsStarted(nextValues)
                return .init(state: state)

            case (.featureIsStarted(let values), .newSetPointWasReceived(let newSetPoint)):
                let nextValues = HeatPumpValues(
                    temperature: values.temperature,
                    setPoint: newSetPoint,
                    unitSymbol: values.unitSymbol
                )
                state = .setPointIsBeingSet(nextValues)
                return .init(state: state, effects: [.updateSetPoint(newSetPoint)])

            case (.setPointIsBeingSet(let values), .valuesWereReceivedFromGateway(let temperature, let setPoint)):
                let nextValues = HeatPumpValues(
                    temperature: temperature,
                    setPoint: setPoint,
                    unitSymbol: values.unitSymbol
                )
                state = .setPointIsBeingSet(nextValues)
                return .init(state: state)

            case (.setPointIsBeingSet(let values), .newSetPointWasReceived(let newSetPoint)):
                let nextValues = HeatPumpValues(
                    temperature: values.temperature,
                    setPoint: newSetPoint,
                    unitSymbol: values.unitSymbol
                )
                state = .setPointIsBeingSet(nextValues)
                return .init(state: state, effects: [.updateSetPoint(newSetPoint)])

            case (.setPointIsBeingSet(let values), .setPointWasConfirmed):
                state = .featureIsStarted(values)
                return .init(state: state)

            default:
                return .init(state: state)
            }
        }
    }

    struct CommandContext: Sendable, Equatable {
        let deviceID: Int
        let endpointID: Int
        let setPointName: String
    }

    private(set) var state: HeatPumpState = .featureIsIdle(HeatPumpValues(temperature: 0.0, setPoint: 0.0))

    private let observeHeatPump: ObserveHeatPumpEffectExecutor
    private let executeSetPoint: ExecuteHeatPumpSetPointEffectExecutor
    private var observationTask: Task<Void, Never>?
    private let setPointThrottler: Throttler<Double>
    private var commandContext: CommandContext?
    private var hasStarted = false

    var temperature: Double {
        state.values.temperature
    }

    var setPoint: Double {
        state.values.setPoint
    }

    var unitSymbol: String {
        state.values.unitSymbol
    }

    var isSetPointBeingSet: Bool {
        if case .setPointIsBeingSet = state {
            return true
        }
        return false
    }

    init(
        observeHeatPump: ObserveHeatPumpEffectExecutor,
        executeSetPoint: ExecuteHeatPumpSetPointEffectExecutor,
        setPointDebounceInterval: DispatchTimeInterval = .seconds(2)
    ) {
        self.observeHeatPump = observeHeatPump
        self.executeSetPoint = executeSetPoint
        self.setPointThrottler = Throttler(dueTime: setPointDebounceInterval)
        self.setPointThrottler.output = { [weak self] value in
            guard let self else { return }
            await self.executeDebouncedSetPoint(value)
        }
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        replaceTask(
            &observationTask,
            with: makeTrackedStreamTask(
                operation: { [observeHeatPump] in
                    await observeHeatPump()
                },
                onEvent: { [weak self] observation in
                    self?.commandContext = observation.commandContext
                    self?.send(
                        .valuesWereReceivedFromGateway(
                            temperature: observation.temperature,
                            setPoint: observation.setPoint
                        )
                    )
                },
                onFinish: { [weak self] in
                    self?.observationTask = nil
                }
            )
        )
    }

    isolated deinit {
        observationTask?.cancel()
        setPointThrottler.cancel()
    }

    func send(_ event: HeatPumpEvent) {
        let transition = StateMachine.reduce(state, event)
        state = transition.state
        handle(transition.effects)
    }

    private func handle(_ effects: [HeatPumpEffect]) {
        for effect in effects {
            handle(effect)
        }
    }

    private func handle(_ effect: HeatPumpEffect) {
        switch effect {
        case .updateSetPoint(let setPoint):
            setPointThrottler.push(setPoint)
        }
    }

    private func executeDebouncedSetPoint(_ setPoint: Double) async {
        if let event = await executeSetPoint(
            setPoint: setPoint,
            commandContext: commandContext
        ) {
            send(event)
        }
    }

    nonisolated static func resolveObservedDevice(
        for identifier: DeviceIdentifier,
        in devices: [Device]
    ) -> Device? {
        let siblingEndpoints = devices.filter { $0.deviceId == identifier.deviceId }
        guard siblingEndpoints.isEmpty == false else { return nil }

        guard let primaryDevice = siblingEndpoints.first(where: { $0.id == identifier })
            ?? siblingEndpoints.first else {
            return nil
        }

        var mergedData: [String: JSONValue] = [:]
        var mergedMetadata: [String: JSONValue] = [:]
        var hasMetadata = false

        for device in siblingEndpoints where device.id != primaryDevice.id {
            mergedData.merge(device.data) { _, next in next }
            if let metadata = device.metadata {
                mergedMetadata.merge(metadata) { _, next in next }
                hasMetadata = true
            }
        }

        mergedData.merge(primaryDevice.data) { _, next in next }
        if let metadata = primaryDevice.metadata {
            mergedMetadata.merge(metadata) { _, next in next }
            hasMetadata = true
        }

        var resolvedDevice = primaryDevice
        resolvedDevice.data = mergedData
        resolvedDevice.metadata = hasMetadata ? mergedMetadata : nil
        return resolvedDevice
    }
}

struct HeatPumpObservation: Sendable, Equatable {
    let temperature: Double
    let setPoint: Double
    let commandContext: HeatPumpStore.CommandContext
}
