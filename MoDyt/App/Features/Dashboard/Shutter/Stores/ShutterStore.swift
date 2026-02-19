import Foundation
import Observation

enum ShutterStep: Int, CaseIterable, Identifiable, Sendable {
    case open = 100
    case threeQuarter = 75
    case half = 50
    case quarter = 25
    case closed = 0

    var id: Int { rawValue }

    var accessibilityLabel: String {
        switch self {
        case .open: return "Open"
        case .threeQuarter: return "Three quarters open"
        case .half: return "Half open"
        case .quarter: return "Quarter open"
        case .closed: return "Closed"
        }
    }
}

struct Positions: Sendable, Equatable {
    let actual: ShutterStep
    let target: ShutterStep
}

enum ShuttersState: Sendable, Equatable {
    case idle(Positions)
    case moving(Positions)

    var positions: Positions {
        switch self {
        case .idle(let positions), .moving(let positions):
            return positions
        }
    }
}

enum ShuttersEvent: Sendable, Equatable {
    case receivedValuesFromStream(actual: ShutterStep, target: ShutterStep)
    case setTarget(value: ShutterStep)
    case failedToComplete
}

enum ShuttersEffect: Sendable, Equatable {
    case startCompletionTimer
    case cancelCompletionTimer
    case handleTarget(value: ShutterStep)
}

enum ShuttersReducer {
    static func reduce(
        state: ShuttersState,
        event: ShuttersEvent
    ) -> (ShuttersState, [ShuttersEffect]) {
        switch (state, event) {
        case let (.idle, .receivedValuesFromStream(actual, target)):
            let nextPositions = Positions(actual: actual, target: target)
            if actual == target {
                return (.idle(nextPositions), [])
            }
            return (.moving(nextPositions), [.startCompletionTimer])

        case let (.idle(current), .setTarget(value)):
            guard value != current.target else {
                return (state, [])
            }
            return (
                .moving(Positions(actual: current.actual, target: value)),
                [.handleTarget(value: value), .startCompletionTimer]
            )

        case (.idle, .failedToComplete):
            return (state, [])

        case let (.moving(current), .receivedValuesFromStream(actual, target)):
            if actual == target {
                return (
                    .idle(Positions(actual: actual, target: target)),
                    [.cancelCompletionTimer]
                )
            }

            if target == current.target {
                return (
                    .moving(Positions(actual: actual, target: current.target)),
                    []
                )
            }

            return (
                .moving(Positions(actual: actual, target: target)),
                [.cancelCompletionTimer, .startCompletionTimer]
            )

        case let (.moving(current), .setTarget(value)):
            guard value != current.target else {
                return (state, [])
            }
            return (
                .moving(Positions(actual: current.actual, target: value)),
                [.handleTarget(value: value), .cancelCompletionTimer, .startCompletionTimer]
            )

        case let (.moving(current), .failedToComplete):
            return (
                .idle(Positions(actual: current.actual, target: current.target)),
                []
            )
        }
    }
}

@Observable
@MainActor
final class ShutterStore {
    struct Dependencies {
        let observePositions: @Sendable ([String]) async -> any AsyncSequence<(actual: ShutterStep, target: ShutterStep), Never> & Sendable
        let sendTargetPosition: @Sendable ([String], ShutterStep) async -> Void
        let startCompletionTimer: @Sendable (@escaping @MainActor @Sendable () -> Void) -> Task<Void, Never>
        let log: @Sendable (String) -> Void

        init(
            observePositions: @escaping @Sendable ([String]) async -> any AsyncSequence<(actual: ShutterStep, target: ShutterStep), Never> & Sendable,
            sendTargetPosition: @escaping @Sendable ([String], ShutterStep) async -> Void,
            startCompletionTimer: @escaping @Sendable (@escaping @MainActor @Sendable () -> Void) -> Task<Void, Never>,
            log: @escaping @Sendable (String) -> Void = { _ in }
        ) {
            self.observePositions = observePositions
            self.sendTargetPosition = sendTargetPosition
            self.startCompletionTimer = startCompletionTimer
            self.log = log
        }
    }

    private(set) var state: ShuttersState

    private let shutterUniqueIds: [String]
    private let dependencies: Dependencies
    private let observationTask = TaskHandle()
    private var completionTimerTask: Task<Void, Never>?
    private let worker: Worker
    private var streamUpdateSequence: UInt64 = 0

    var actualStep: ShutterStep {
        state.positions.actual
    }

    var targetStep: ShutterStep {
        state.positions.target
    }

    var isMoving: Bool {
        if case .moving = state {
            return true
        }
        return false
    }

    init(
        shutterUniqueIds: [String],
        dependencies: Dependencies
    ) {
        self.state = .idle(Positions(actual: .open, target: .open))
        self.shutterUniqueIds = shutterUniqueIds
        self.dependencies = dependencies
        self.worker = Worker(
            observePositions: dependencies.observePositions,
            sendTargetPosition: dependencies.sendTargetPosition
        )
        let ids = shutterUniqueIds.joined(separator: ",")
        dependencies.log("ShutterTrace store init ids=\(ids)")

        observationTask.task = Task { [weak self, worker, shutterUniqueIds] in
            await worker.observePositions(shutterUniqueIds: shutterUniqueIds) { [weak self] actual, target in
                self?.send(.receivedValuesFromStream(actual: actual, target: target))
            }
        }
    }

    deinit {
        let ids = shutterUniqueIds.joined(separator: ",")
        dependencies.log("ShutterTrace store deinit ids=\(ids)")
    }

    func send(_ event: ShuttersEvent) {
        let traceToken = nextTraceToken(for: event)
        let previousState = state
        let (nextState, effects) = ShuttersReducer.reduce(state: state, event: event)
        state = nextState
        let ids = shutterUniqueIds.joined(separator: ",")
        let effectSummary = effects.map(Self.describeEffect).joined(separator: ",")
        dependencies.log(
            "ShutterStore transition ids=\(ids) trace=\(traceToken) event=\(Self.describeEvent(event)) actual=\(previousState.positions.actual.rawValue)->\(nextState.positions.actual.rawValue) target=\(previousState.positions.target.rawValue)->\(nextState.positions.target.rawValue) moving=\(Self.isMoving(previousState))->\(Self.isMoving(nextState)) effects=[\(effectSummary)]"
        )
        handle(effects)
    }

    private func nextTraceToken(for event: ShuttersEvent) -> String {
        switch event {
        case .receivedValuesFromStream:
            streamUpdateSequence += 1
            return "stream-\(streamUpdateSequence)"
        case .setTarget:
            return "target-\(streamUpdateSequence)"
        case .failedToComplete:
            return "timer-\(streamUpdateSequence)"
        }
    }

    private func handle(_ effects: [ShuttersEffect]) {
        for effect in effects {
            handle(effect)
        }
    }

    private func handle(_ effect: ShuttersEffect) {
        switch effect {
        case .startCompletionTimer:
            completionTimerTask?.cancel()
            completionTimerTask = dependencies.startCompletionTimer { [weak self] in
                guard let self else { return }
                self.completionTimerTask = nil
                self.send(.failedToComplete)
            }

        case .cancelCompletionTimer:
            completionTimerTask?.cancel()
            completionTimerTask = nil

        case .handleTarget(let value):
            let shutterUniqueIds = self.shutterUniqueIds
            Task { [worker] in
                await worker.sendTargetPosition(
                    shutterUniqueIds: shutterUniqueIds,
                    target: value
                )
            }
        }
    }

    private actor Worker {
        private let observePositionsSource: @Sendable ([String]) async -> any AsyncSequence<(actual: ShutterStep, target: ShutterStep), Never> & Sendable
        private let sendTargetPositionAction: @Sendable ([String], ShutterStep) async -> Void

        init(
            observePositions: @escaping @Sendable ([String]) async -> any AsyncSequence<(actual: ShutterStep, target: ShutterStep), Never> & Sendable,
            sendTargetPosition: @escaping @Sendable ([String], ShutterStep) async -> Void
        ) {
            self.observePositionsSource = observePositions
            self.sendTargetPositionAction = sendTargetPosition
        }

        func observePositions(
            shutterUniqueIds: [String],
            onUpdate: @escaping @MainActor @Sendable (ShutterStep, ShutterStep) -> Void
        ) async {
            let stream = await observePositionsSource(shutterUniqueIds)
            for await values in stream {
                guard !Task.isCancelled else { return }
                await onUpdate(values.actual, values.target)
            }
        }

        func sendTargetPosition(
            shutterUniqueIds: [String],
            target: ShutterStep
        ) async {
            await sendTargetPositionAction(shutterUniqueIds, target)
        }
    }

    private static func isMoving(_ state: ShuttersState) -> Bool {
        if case .moving = state {
            return true
        }
        return false
    }

    private static func describeEvent(_ event: ShuttersEvent) -> String {
        switch event {
        case .receivedValuesFromStream(let actual, let target):
            return "receivedValuesFromStream(actual:\(actual.rawValue),target:\(target.rawValue))"
        case .setTarget(let value):
            return "setTarget(value:\(value.rawValue))"
        case .failedToComplete:
            return "failedToComplete"
        }
    }

    private static func describeEffect(_ effect: ShuttersEffect) -> String {
        switch effect {
        case .startCompletionTimer:
            return "startCompletionTimer"
        case .cancelCompletionTimer:
            return "cancelCompletionTimer"
        case .handleTarget(let value):
            return "handleTarget(value:\(value.rawValue))"
        }
    }
}

private final class TaskHandle {
    var task: Task<Void, Never>? {
        didSet { oldValue?.cancel() }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    deinit {
        task?.cancel()
    }
}
