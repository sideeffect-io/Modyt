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

enum HeatPumpReducer {
    static func reduce(
        state: HeatPumpState,
        event: HeatPumpEvent
    ) -> (HeatPumpState, [HeatPumpEffect]) {
        switch (state, event) {
        case (.featureIsIdle(let values), .valuesWereReceivedFromGateway(let temperature, let setPoint)):
            let nextValues = HeatPumpValues(
                temperature: temperature,
                setPoint: setPoint,
                unitSymbol: values.unitSymbol
            )
            return (.featureIsStarted(nextValues), [])

        case (.featureIsStarted(let values), .valuesWereReceivedFromGateway(let temperature, let setPoint)):
            let nextValues = HeatPumpValues(
                temperature: temperature,
                setPoint: setPoint,
                unitSymbol: values.unitSymbol
            )
            return (.featureIsStarted(nextValues), [])

        case (.featureIsStarted(let values), .newSetPointWasReceived(let newSetPoint)):
            let nextValues = HeatPumpValues(
                temperature: values.temperature,
                setPoint: newSetPoint,
                unitSymbol: values.unitSymbol
            )
            return (
                .setPointIsBeingSet(nextValues),
                [.updateSetPoint(newSetPoint)]
            )

        case (.setPointIsBeingSet(let values), .valuesWereReceivedFromGateway(let temperature, let setPoint)):
            let nextValues = HeatPumpValues(
                temperature: temperature,
                setPoint: setPoint,
                unitSymbol: values.unitSymbol
            )
            return (.setPointIsBeingSet(nextValues), [])

        case (.setPointIsBeingSet(let values), .newSetPointWasReceived(let newSetPoint)):
            let nextValues = HeatPumpValues(
                temperature: values.temperature,
                setPoint: newSetPoint,
                unitSymbol: values.unitSymbol
            )
            return (
                .setPointIsBeingSet(nextValues),
                [.updateSetPoint(newSetPoint)]
            )

        case (.setPointIsBeingSet(let values), .setPointWasConfirmed):
            return (.featureIsStarted(values), [])

        default:
            return (state, [])
        }
    }
}

@Observable
@MainActor
final class HeatPumpStore {
    private struct CommandContext: Sendable, Equatable {
        let deviceID: Int
        let endpointID: Int
        let setPointName: String
    }

    struct Dependencies {
        let observeHeatPump: @Sendable (String) async -> any AsyncSequence<Device?, Never> & Sendable
        let executeSetPointCommand: @Sendable (HeatPumpGatewayCommand) async -> Void
        let makeTransactionID: @Sendable () async -> String
        let setPointDebounceInterval: DispatchTimeInterval

        init(
            observeHeatPump: @escaping @Sendable (String) async -> any AsyncSequence<Device?, Never> & Sendable,
            executeSetPointCommand: @escaping @Sendable (HeatPumpGatewayCommand) async -> Void,
            makeTransactionID: @escaping @Sendable () async -> String = {
                TydomCommand.defaultTransactionId(now: Date.init)
            },
            setPointDebounceInterval: DispatchTimeInterval = .seconds(2)
        ) {
            self.observeHeatPump = observeHeatPump
            self.executeSetPointCommand = executeSetPointCommand
            self.makeTransactionID = makeTransactionID
            self.setPointDebounceInterval = setPointDebounceInterval
        }
    }

    private(set) var state: HeatPumpState

    private let dependencies: Dependencies
    private let observationTask = TaskHandle()
    private let worker: Worker
    private let setPointThrottler: Throttler<Double>
    private var commandContext: CommandContext?

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
        uniqueId: String,
        dependencies: Dependencies
    ) {
        self.state = .featureIsIdle(HeatPumpValues(temperature: 0.0, setPoint: 0.0))
        self.dependencies = dependencies
        self.setPointThrottler = Throttler(dueTime: dependencies.setPointDebounceInterval)
        self.worker = Worker(
            observeHeatPump: dependencies.observeHeatPump,
            executeSetPointCommand: dependencies.executeSetPointCommand
        )
        self.setPointThrottler.output = { [weak self] value in
            guard let self else { return }
            await self.executeDebouncedSetPoint(value)
        }

        observationTask.task = Task { [weak self, worker, uniqueId] in
            await worker.observeHeatPump(uniqueId: uniqueId) { [weak self] observation in
                self?.commandContext = observation.commandContext
                self?.send(
                    .valuesWereReceivedFromGateway(
                        temperature: observation.temperature,
                        setPoint: observation.setPoint
                    )
                )
            }
        }
    }

    func send(_ event: HeatPumpEvent) {
        let (nextState, effects) = HeatPumpReducer.reduce(state: state, event: event)
        state = nextState
        handle(effects)
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
        guard let command = await buildGatewayCommand(setPoint: setPoint) else {
            send(.setPointWasConfirmed)
            return
        }
        await worker.executeSetPointCommand(command)
        send(.setPointWasConfirmed)
    }

    private func buildGatewayCommand(setPoint: Double) async -> HeatPumpGatewayCommand? {
        guard let commandContext else { return nil }
        let transactionId = await dependencies.makeTransactionID()
        let command = TydomCommand.putDevicesData(
            deviceId: String(commandContext.deviceID),
            endpointId: String(commandContext.endpointID),
            name: commandContext.setPointName,
            value: .string(Self.formattedSetPoint(setPoint)),
            transactionId: transactionId
        )
        return HeatPumpGatewayCommand(
            request: command.request,
            transactionId: transactionId
        )
    }

    private static func formattedSetPoint(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private actor Worker {
        struct Observation: Sendable {
            let temperature: Double
            let setPoint: Double
            let commandContext: CommandContext
        }

        private let observeHeatPumpSource: @Sendable (String) async -> any AsyncSequence<Device?, Never> & Sendable
        private let executeSetPointCommandAction: @Sendable (HeatPumpGatewayCommand) async -> Void

        init(
            observeHeatPump: @escaping @Sendable (String) async -> any AsyncSequence<Device?, Never> & Sendable,
            executeSetPointCommand: @escaping @Sendable (HeatPumpGatewayCommand) async -> Void
        ) {
            self.observeHeatPumpSource = observeHeatPump
            self.executeSetPointCommandAction = executeSetPointCommand
        }

        func observeHeatPump(
            uniqueId: String,
            onObservation: @escaping @MainActor @Sendable (Observation) -> Void
        ) async {
            let stream = await observeHeatPumpSource(uniqueId)
            for await device in stream {
                guard !Task.isCancelled else { return }
                guard let device else { continue }
                guard let values = device.heatPumpGatewayValues() else { continue }
                guard let setPointName = device.heatPumpSetpointKey() else { continue }
                await onObservation(
                    Observation(
                        temperature: values.temperature,
                        setPoint: values.setPoint,
                        commandContext: CommandContext(
                            deviceID: device.deviceID,
                            endpointID: device.endpointId,
                            setPointName: setPointName
                        )
                    )
                )
            }
        }

        func executeSetPointCommand(_ command: HeatPumpGatewayCommand) async {
            await executeSetPointCommandAction(command)
        }
    }
}

private final class TaskHandle {
    var task: Task<Void, Never>? {
        didSet { oldValue?.cancel() }
    }

    deinit {
        task?.cancel()
    }
}
