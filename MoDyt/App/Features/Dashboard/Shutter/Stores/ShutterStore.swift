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

enum TargetTrust: Sendable, Equatable {
    case trusted
    case acknowledged(staleStreamTarget: Int)
}

struct Positions: Sendable, Equatable {
    let actual: Int
    let target: Int
    let targetTrust: TargetTrust
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
    case receivedValuesFromStream(actual: Int, target: Int)
    case setTarget(value: Int)
    case failedToComplete
}

enum ShuttersEffect: Sendable, Equatable {
    case startCompletionTimer
    case cancelCompletionTimer
    case handleTarget(value: Int)
    case syncTargetCache(value: Int)
}

enum ShuttersReducer {
    static func reduce(
        state: ShuttersState,
        event: ShuttersEvent
    ) -> (ShuttersState, [ShuttersEffect]) {
        switch (state, event) {
        case let (.idle(current), .receivedValuesFromStream(actual, target)):
            if actual == target {
                let nextPositions = Positions(
                    actual: actual,
                    target: target,
                    targetTrust: .trusted
                )
                return (.idle(nextPositions), [])
            }

            let isStreamTargetChanged = target != current.target
            let nextTarget = if isStreamTargetChanged {
                target
            } else {
                actual
            }
            let trust: TargetTrust = if isStreamTargetChanged {
                .trusted
            } else {
                .acknowledged(staleStreamTarget: target)
            }
            let nextPositions = Positions(
                actual: isStreamTargetChanged ? actual : current.actual,
                target: nextTarget,
                targetTrust: trust
            )
            return (.moving(nextPositions), [.startCompletionTimer])

        case let (.idle(current), .setTarget(value)):
            guard value != current.target else {
                return (state, [])
            }
            let nextPositions = Positions(
                actual: current.actual,
                target: value,
                targetTrust: .trusted
            )
            return (
                .moving(nextPositions),
                [.handleTarget(value: value), .startCompletionTimer]
            )

        case (.idle, .failedToComplete):
            return (state, [])

        case let (.moving(current), .receivedValuesFromStream(actual, target)):
            if case .acknowledged(let staleTarget) = current.targetTrust {
                if target == staleTarget {
                    if actual == current.target {
                        let nextPositions = Positions(
                            actual: actual,
                            target: current.target,
                            targetTrust: .trusted
                        )
                        return (
                            .idle(nextPositions),
                            [
                                .cancelCompletionTimer,
                                .syncTargetCache(value: current.target),
                            ]
                        )
                    }

                    let nextPositions = Positions(
                        actual: actual,
                        target: current.target,
                        targetTrust: current.targetTrust
                    )
                    let effects: [ShuttersEffect] = if actual == current.actual {
                        []
                    } else {
                        [.cancelCompletionTimer, .startCompletionTimer]
                    }
                    return (
                        .moving(nextPositions),
                        effects
                    )
                }
            }

            if actual == target {
                let nextPositions = Positions(
                    actual: actual,
                    target: target,
                    targetTrust: .trusted
                )
                return (
                    .idle(nextPositions),
                    [.cancelCompletionTimer]
                )
            }

            if target == current.target {
                let trust: TargetTrust = if case .acknowledged = current.targetTrust {
                    .trusted
                } else {
                    current.targetTrust
                }
                let nextPositions = Positions(
                    actual: actual,
                    target: current.target,
                    targetTrust: trust
                )
                let effects: [ShuttersEffect] = if actual == current.actual {
                    []
                } else {
                    [.cancelCompletionTimer, .startCompletionTimer]
                }
                return (
                    .moving(nextPositions),
                    effects
                )
            }

            let nextPositions = Positions(
                actual: actual,
                target: target,
                targetTrust: .trusted
            )
            return (
                .moving(nextPositions),
                [.cancelCompletionTimer, .startCompletionTimer]
            )

        case let (.moving(current), .setTarget(value)):
            guard value != current.target else {
                return (state, [])
            }
            let nextPositions = Positions(
                actual: current.actual,
                target: value,
                targetTrust: .trusted
            )
            return (
                .moving(nextPositions),
                [.handleTarget(value: value), .cancelCompletionTimer, .startCompletionTimer]
            )

        case let (.moving(current), .failedToComplete):
            let target = if case .acknowledged = current.targetTrust {
                current.actual
            } else {
                current.target
            }
            let nextPositions = Positions(
                actual: current.actual,
                target: target,
                targetTrust: .trusted
            )
            return (
                .idle(nextPositions),
                []
            )
        }
    }
}

@Observable
@MainActor
final class ShutterStore {
    struct Dependencies {
        let observePositions: @Sendable ([String]) async -> any AsyncSequence<(actual: Int, target: Int), Never> & Sendable
        let sendTargetPosition: @Sendable ([String], Int) async -> Void
        let syncTargetCache: @Sendable ([String], Int) async -> Void
        let startCompletionTimer: @Sendable (@escaping @MainActor @Sendable () -> Void) -> Task<Void, Never>
        let log: @Sendable (String) -> Void

        init(
            observePositions: @escaping @Sendable ([String]) async -> any AsyncSequence<(actual: Int, target: Int), Never> & Sendable,
            sendTargetPosition: @escaping @Sendable ([String], Int) async -> Void,
            syncTargetCache: @escaping @Sendable ([String], Int) async -> Void = { _, _ in },
            startCompletionTimer: @escaping @Sendable (@escaping @MainActor @Sendable () -> Void) -> Task<Void, Never>,
            log: @escaping @Sendable (String) -> Void = { _ in }
        ) {
            self.observePositions = observePositions
            self.sendTargetPosition = sendTargetPosition
            self.syncTargetCache = syncTargetCache
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

    var actualPosition: Int {
        state.positions.actual
    }

    var targetPosition: Int {
        state.positions.target
    }

    var isTargetReliable: Bool {
        switch state.positions.targetTrust {
        case .trusted, .acknowledged:
            return true
        }
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
        self.state = .idle(Positions(actual: 100, target: 100, targetTrust: .trusted))
        self.shutterUniqueIds = shutterUniqueIds
        self.dependencies = dependencies
        self.worker = Worker(
            observePositions: dependencies.observePositions,
            sendTargetPosition: dependencies.sendTargetPosition,
            syncTargetCache: dependencies.syncTargetCache
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
            "ShutterStore transition ids=\(ids) trace=\(traceToken) event=\(Self.describeEvent(event)) actual=\(previousState.positions.actual)->\(nextState.positions.actual) target=\(previousState.positions.target)->\(nextState.positions.target) trust=\(previousState.positions.targetTrust)->\(nextState.positions.targetTrust) moving=\(Self.isMoving(previousState))->\(Self.isMoving(nextState)) effects=[\(effectSummary)]"
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

        case .syncTargetCache(let value):
            guard shutterUniqueIds.count == 1 else {
                let ids = shutterUniqueIds.joined(separator: ",")
                dependencies.log(
                    "Shutter target sync skipped ids=\(ids) reason=multi-id-store inferredTarget=\(value)"
                )
                return
            }
            let shutterUniqueIds = self.shutterUniqueIds
            Task { [worker] in
                await worker.syncTargetCache(
                    shutterUniqueIds: shutterUniqueIds,
                    target: value
                )
            }
        }
    }

    private actor Worker {
        private let observePositionsSource: @Sendable ([String]) async -> any AsyncSequence<(actual: Int, target: Int), Never> & Sendable
        private let sendTargetPositionAction: @Sendable ([String], Int) async -> Void
        private let syncTargetCacheAction: @Sendable ([String], Int) async -> Void

        init(
            observePositions: @escaping @Sendable ([String]) async -> any AsyncSequence<(actual: Int, target: Int), Never> & Sendable,
            sendTargetPosition: @escaping @Sendable ([String], Int) async -> Void,
            syncTargetCache: @escaping @Sendable ([String], Int) async -> Void
        ) {
            self.observePositionsSource = observePositions
            self.sendTargetPositionAction = sendTargetPosition
            self.syncTargetCacheAction = syncTargetCache
        }

        func observePositions(
            shutterUniqueIds: [String],
            onUpdate: @escaping @MainActor @Sendable (Int, Int) -> Void
        ) async {
            let stream = await observePositionsSource(shutterUniqueIds)
            for await values in stream {
                guard !Task.isCancelled else { return }
                await onUpdate(values.actual, values.target)
            }
        }

        func sendTargetPosition(
            shutterUniqueIds: [String],
            target: Int
        ) async {
            await sendTargetPositionAction(shutterUniqueIds, target)
        }

        func syncTargetCache(
            shutterUniqueIds: [String],
            target: Int
        ) async {
            await syncTargetCacheAction(shutterUniqueIds, target)
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
            return "receivedValuesFromStream(actual:\(actual),target:\(target))"
        case .setTarget(let value):
            return "setTarget(value:\(value))"
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
            return "handleTarget(value:\(value))"
        case .syncTargetCache(let value):
            return "syncTargetCache(value:\(value))"
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
