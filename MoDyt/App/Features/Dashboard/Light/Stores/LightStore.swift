import Foundation
import Observation
import DeltaDoreClient

@Observable
@MainActor
final class LightStore: StartableStore {
    struct ControlChange: Sendable, Equatable {
        let key: String
        let value: PayloadValue
    }

    enum State: Sendable {
        case featureIsIdle(uniqueId: String, descriptor: DrivingLightControlDescriptor)
        case featureIsStarted(uniqueId: String, descriptor: DrivingLightControlDescriptor)
        case lightIsChangingInApp(
            uniqueId: String,
            descriptor: DrivingLightControlDescriptor,
            expectedDescriptor: DrivingLightControlDescriptor,
            suppressedIncomingDescriptor: DrivingLightControlDescriptor?,
            timeoutTask: Task<Void, Never>? = nil
        )

        var uniqueId: String {
            switch self {
            case .featureIsIdle(let uniqueId, _),
                 .featureIsStarted(let uniqueId, _),
                 .lightIsChangingInApp(let uniqueId, _, _, _, _):
                return uniqueId
            }
        }

        var descriptor: DrivingLightControlDescriptor {
            switch self {
            case .featureIsIdle(_, let descriptor),
                 .featureIsStarted(_, let descriptor),
                 .lightIsChangingInApp(_, let descriptor, _, _, _):
                return descriptor
            }
        }

        var timeoutTask: Task<Void, Never>? {
            if case .lightIsChangingInApp(_, _, _, _, let timeoutTask) = self {
                return timeoutTask
            }
            return nil
        }

        var isChangingInApp: Bool {
            if case .lightIsChangingInApp = self {
                return true
            }
            return false
        }
    }

    enum Event: Sendable {
        case powerWasSetInApp(Bool)
        case levelNormalizedWasSetInApp(Double)
        case descriptorWasReceived(DrivingLightControlDescriptor)
        case timeoutHasExpired
        case timeoutTaskWasCreated(task: Task<Void, Never>)
    }

    enum Effect: Sendable {
        case cancelTimeout(task: Task<Void, Never>?)
        case sendControlChanges(uniqueId: String, changes: [ControlChange])
        case startTimeout
    }

    struct StateMachine {
        var state: State = .featureIsIdle(
            uniqueId: "",
            descriptor: LightStore.fallbackDescriptor
        )

        mutating func reduce(_ event: Event) -> [Effect] {
            reduce(event, uniqueId: state.uniqueId)
        }

        mutating func reduce(_ event: Event, uniqueId: String) -> [Effect] {
            switch (state, event) {
            case let (.featureIsIdle(_, _), .descriptorWasReceived(descriptor)):
                state = .featureIsStarted(uniqueId: uniqueId, descriptor: descriptor)
                return []

            case let (.featureIsStarted(uniqueId, currentDescriptor), .descriptorWasReceived(descriptor)):
                guard descriptor != currentDescriptor else { return [] }
                state = .featureIsStarted(uniqueId: uniqueId, descriptor: descriptor)
                return []

            case let (.featureIsStarted(uniqueId, currentDescriptor), .powerWasSetInApp(isOn)):
                guard let planned = Self.planForPowerChange(
                    currentDescriptor: currentDescriptor,
                    isOn: isOn
                ) else {
                    return []
                }

                state = .lightIsChangingInApp(
                    uniqueId: uniqueId,
                    descriptor: planned.descriptor,
                    expectedDescriptor: planned.descriptor,
                    suppressedIncomingDescriptor: nil,
                    timeoutTask: nil
                )

                return [
                    .sendControlChanges(uniqueId: uniqueId, changes: planned.changes),
                    .startTimeout,
                ]

            case let (.featureIsStarted(uniqueId, currentDescriptor), .levelNormalizedWasSetInApp(normalizedLevel)):
                guard let planned = Self.planForLevelChange(
                    currentDescriptor: currentDescriptor,
                    normalizedLevel: normalizedLevel
                ) else {
                    return []
                }

                state = .lightIsChangingInApp(
                    uniqueId: uniqueId,
                    descriptor: planned.descriptor,
                    expectedDescriptor: planned.descriptor,
                    suppressedIncomingDescriptor: nil,
                    timeoutTask: nil
                )

                return [
                    .sendControlChanges(uniqueId: uniqueId, changes: planned.changes),
                    .startTimeout,
                ]

            case let (
                .lightIsChangingInApp(uniqueId, currentDescriptor, _, _, timeoutTask),
                .powerWasSetInApp(isOn)
            ):
                guard let planned = Self.planForPowerChange(
                    currentDescriptor: currentDescriptor,
                    isOn: isOn
                ) else {
                    return []
                }

                state = .lightIsChangingInApp(
                    uniqueId: uniqueId,
                    descriptor: planned.descriptor,
                    expectedDescriptor: planned.descriptor,
                    suppressedIncomingDescriptor: nil,
                    timeoutTask: nil
                )

                return [
                    .cancelTimeout(task: timeoutTask),
                    .sendControlChanges(uniqueId: uniqueId, changes: planned.changes),
                    .startTimeout,
                ]

            case let (
                .lightIsChangingInApp(uniqueId, currentDescriptor, _, _, timeoutTask),
                .levelNormalizedWasSetInApp(normalizedLevel)
            ):
                guard let planned = Self.planForLevelChange(
                    currentDescriptor: currentDescriptor,
                    normalizedLevel: normalizedLevel
                ) else {
                    return []
                }

                state = .lightIsChangingInApp(
                    uniqueId: uniqueId,
                    descriptor: planned.descriptor,
                    expectedDescriptor: planned.descriptor,
                    suppressedIncomingDescriptor: nil,
                    timeoutTask: nil
                )

                return [
                    .cancelTimeout(task: timeoutTask),
                    .sendControlChanges(uniqueId: uniqueId, changes: planned.changes),
                    .startTimeout,
                ]

            case let (
                .lightIsChangingInApp(
                    uniqueId,
                    currentDescriptor,
                    expectedDescriptor,
                    _,
                    timeoutTask
                ),
                .descriptorWasReceived(incomingDescriptor)
            ):
                if Self.matchesExpectedDescriptor(
                    incomingDescriptor,
                    expected: expectedDescriptor
                ) {
                    state = .featureIsStarted(
                        uniqueId: uniqueId,
                        descriptor: incomingDescriptor
                    )
                    return [.cancelTimeout(task: timeoutTask)]
                }

                state = .lightIsChangingInApp(
                    uniqueId: uniqueId,
                    descriptor: currentDescriptor,
                    expectedDescriptor: expectedDescriptor,
                    suppressedIncomingDescriptor: incomingDescriptor,
                    timeoutTask: timeoutTask
                )
                return []

            case let (
                .lightIsChangingInApp(
                    uniqueId,
                    descriptor,
                    _,
                    suppressedIncomingDescriptor,
                    timeoutTask
                ),
                .timeoutHasExpired
            ):
                state = .featureIsStarted(
                    uniqueId: uniqueId,
                    descriptor: suppressedIncomingDescriptor ?? descriptor
                )
                return [.cancelTimeout(task: timeoutTask)]

            case let (
                .lightIsChangingInApp(
                    uniqueId,
                    descriptor,
                    expectedDescriptor,
                    suppressedIncomingDescriptor,
                    _
                ),
                .timeoutTaskWasCreated(timeoutTask)
            ):
                state = .lightIsChangingInApp(
                    uniqueId: uniqueId,
                    descriptor: descriptor,
                    expectedDescriptor: expectedDescriptor,
                    suppressedIncomingDescriptor: suppressedIncomingDescriptor,
                    timeoutTask: timeoutTask
                )
                return []

            default:
                return []
            }
        }

        private static func planForPowerChange(
            currentDescriptor: DrivingLightControlDescriptor,
            isOn: Bool
        ) -> (descriptor: DrivingLightControlDescriptor, changes: [ControlChange])? {
            guard currentDescriptor.isOn != isOn else { return nil }

            if let powerKey = currentDescriptor.powerKey {
                let nextDescriptor = DrivingLightControlDescriptor(
                    powerKey: currentDescriptor.powerKey,
                    levelKey: currentDescriptor.levelKey,
                    isOn: isOn,
                    level: currentDescriptor.levelKey == nil
                        ? (isOn ? currentDescriptor.range.upperBound : currentDescriptor.range.lowerBound)
                        : currentDescriptor.level,
                    range: currentDescriptor.range
                )

                return (
                    descriptor: nextDescriptor,
                    changes: [.init(key: powerKey, value: .bool(isOn))]
                )
            }

            guard let levelKey = currentDescriptor.levelKey else { return nil }
            let targetLevel = isOn
                ? currentDescriptor.range.upperBound
                : currentDescriptor.range.lowerBound
            let nextDescriptor = DrivingLightControlDescriptor(
                powerKey: currentDescriptor.powerKey,
                levelKey: currentDescriptor.levelKey,
                isOn: isOn,
                level: targetLevel,
                range: currentDescriptor.range
            )
            return (
                descriptor: nextDescriptor,
                changes: [.init(key: levelKey, value: .number(targetLevel))]
            )
        }

        private static func planForLevelChange(
            currentDescriptor: DrivingLightControlDescriptor,
            normalizedLevel: Double
        ) -> (descriptor: DrivingLightControlDescriptor, changes: [ControlChange])? {
            let clampedNormalized = min(max(normalizedLevel, 0), 1)

            guard let levelKey = currentDescriptor.levelKey else {
                guard let powerKey = currentDescriptor.powerKey else { return nil }
                let shouldBeOn = clampedNormalized > 0.01
                guard currentDescriptor.isOn != shouldBeOn else { return nil }

                let nextDescriptor = DrivingLightControlDescriptor(
                    powerKey: currentDescriptor.powerKey,
                    levelKey: currentDescriptor.levelKey,
                    isOn: shouldBeOn,
                    level: shouldBeOn
                        ? currentDescriptor.range.upperBound
                        : currentDescriptor.range.lowerBound,
                    range: currentDescriptor.range
                )

                return (
                    descriptor: nextDescriptor,
                    changes: [.init(key: powerKey, value: .bool(shouldBeOn))]
                )
            }

            let targetLevel = currentDescriptor.range.lowerBound
                + (currentDescriptor.range.upperBound - currentDescriptor.range.lowerBound) * clampedNormalized
            let clampedTargetLevel = min(
                max(targetLevel, currentDescriptor.range.lowerBound),
                currentDescriptor.range.upperBound
            )

            let previousIsOn = currentDescriptor.isOn
            let nextDescriptor = DrivingLightControlDescriptor(
                powerKey: currentDescriptor.powerKey,
                levelKey: currentDescriptor.levelKey,
                isOn: clampedTargetLevel > currentDescriptor.range.lowerBound,
                level: clampedTargetLevel,
                range: currentDescriptor.range
            )

            guard nextDescriptor != currentDescriptor else { return nil }

            var changes: [ControlChange] = [
                .init(key: levelKey, value: .number(clampedTargetLevel))
            ]

            if let powerKey = nextDescriptor.powerKey, nextDescriptor.isOn != previousIsOn {
                changes.append(.init(key: powerKey, value: .bool(nextDescriptor.isOn)))
            }

            return (descriptor: nextDescriptor, changes: changes)
        }

        private static func matchesExpectedDescriptor(
            _ incoming: DrivingLightControlDescriptor,
            expected: DrivingLightControlDescriptor
        ) -> Bool {
            guard incoming.powerKey == expected.powerKey,
                  incoming.levelKey == expected.levelKey,
                  incoming.range == expected.range else {
                return false
            }

            let normalizedDelta = abs(incoming.normalizedLevel - expected.normalizedLevel)
            let levelMatches = normalizedDelta <= LightStore.pendingNormalizedTolerance
                || expected.levelKey == nil
            let powerMatches = incoming.powerKey == nil || incoming.isOn == expected.isOn
            return levelMatches && powerMatches
        }
    }

    struct Dependencies {
        let observeLightDescriptor: @Sendable (String) async -> any AsyncSequence<DrivingLightControlDescriptor?, Never> & Sendable
        let applyOptimisticChanges: @Sendable (String, [String: PayloadValue]) async -> Void
        let sendCommand: @Sendable (String, String, PayloadValue) async -> Void
        let sleep: @Sendable (Duration) async throws -> Void

        init(
            observeLightDescriptor: @escaping @Sendable (String) async -> any AsyncSequence<DrivingLightControlDescriptor?, Never> & Sendable,
            applyOptimisticChanges: @escaping @Sendable (String, [String: PayloadValue]) async -> Void,
            sendCommand: @escaping @Sendable (String, String, PayloadValue) async -> Void,
            sleep: @escaping @Sendable (Duration) async throws -> Void
        ) {
            self.observeLightDescriptor = observeLightDescriptor
            self.applyOptimisticChanges = applyOptimisticChanges
            self.sendCommand = sendCommand
            self.sleep = sleep
        }
    }

    private(set) var stateMachine: StateMachine = StateMachine()

    var state: State {
        stateMachine.state
    }

    var descriptor: DrivingLightControlDescriptor {
        state.descriptor
    }

    var isChangingInApp: Bool {
        state.isChangingInApp
    }

    private let dependencies: Dependencies
    private let uniqueId: String
    private let observationTask = TaskHandle()
    private let worker: Worker
    private var hasStarted = false

    nonisolated private static let pendingEchoSuppressionDuration: Duration = .milliseconds(900)
    nonisolated private static let pendingNormalizedTolerance: Double = 0.03

    init(
        uniqueId: String,
        dependencies: Dependencies
    ) {
        self.dependencies = dependencies
        self.uniqueId = uniqueId
        self.worker = Worker(
            observeLightDescriptor: dependencies.observeLightDescriptor,
            applyOptimisticChanges: dependencies.applyOptimisticChanges,
            sendCommand: dependencies.sendCommand
        )
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        let uniqueId = self.uniqueId

        observationTask.task = Task { [weak self, worker] in
            await worker.observe(uniqueId: uniqueId) { [weak self] descriptor in
                await self?.send(.descriptorWasReceived(descriptor))
            }
        }
    }

    deinit {
        observationTask.cancel()
    }

    func setPower(_ isOn: Bool) {
        send(.powerWasSetInApp(isOn))
    }

    func setLevelNormalized(_ normalized: Double) {
        send(.levelNormalizedWasSetInApp(normalized))
    }

    func send(_ event: Event) {
        let effects = stateMachine.reduce(event, uniqueId: uniqueId)
        handle(effects)
    }

    private func handle(_ effects: [Effect]) {
        for effect in effects {
            switch effect {
            case .cancelTimeout(let timeoutTask):
                timeoutTask?.cancel()

            case .sendControlChanges(let uniqueId, let changes):
                Task { [worker] in
                    await worker.send(uniqueId: uniqueId, changes: changes)
                }

            case .startTimeout:
                startTimeoutIfNeeded()
            }
        }
    }

    private func startTimeoutIfNeeded() {
        guard case .lightIsChangingInApp = state else {
            return
        }

        let timeoutTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await dependencies.sleep(Self.pendingEchoSuppressionDuration)
                self.send(.timeoutHasExpired)
            } catch {
                return
            }
        }

        send(.timeoutTaskWasCreated(task: timeoutTask))
    }

    nonisolated private static let fallbackDescriptor = DrivingLightControlDescriptor(
        powerKey: "on",
        levelKey: nil,
        isOn: false,
        level: 0,
        range: 0...100
    )

    private actor Worker {
        private let observeLightDescriptor: @Sendable (String) async -> any AsyncSequence<DrivingLightControlDescriptor?, Never> & Sendable
        private let applyOptimisticChanges: @Sendable (String, [String: PayloadValue]) async -> Void
        private let sendCommand: @Sendable (String, String, PayloadValue) async -> Void

        init(
            observeLightDescriptor: @escaping @Sendable (String) async -> any AsyncSequence<DrivingLightControlDescriptor?, Never> & Sendable,
            applyOptimisticChanges: @escaping @Sendable (String, [String: PayloadValue]) async -> Void,
            sendCommand: @escaping @Sendable (String, String, PayloadValue) async -> Void
        ) {
            self.observeLightDescriptor = observeLightDescriptor
            self.applyOptimisticChanges = applyOptimisticChanges
            self.sendCommand = sendCommand
        }

        func observe(
            uniqueId: String,
            onDescriptor: @escaping @Sendable (DrivingLightControlDescriptor) async -> Void
        ) async {
            let stream = await observeLightDescriptor(uniqueId)
            var previousDescriptor: DrivingLightControlDescriptor?

            for await descriptor in stream {
                guard !Task.isCancelled else { return }
                guard let descriptor else { continue }

                if descriptor == previousDescriptor {
                    continue
                }

                await onDescriptor(descriptor)
                previousDescriptor = descriptor
            }
        }

        func send(uniqueId: String, changes: [ControlChange]) async {
            guard !changes.isEmpty else { return }

            var optimisticChanges: [String: PayloadValue] = [:]
            optimisticChanges.reserveCapacity(changes.count)
            for change in changes {
                optimisticChanges[change.key] = change.value
            }

            await applyOptimisticChanges(uniqueId, optimisticChanges)
            for change in changes {
                await sendCommand(uniqueId, change.key, change.value)
            }
        }
    }
}

extension LightStore.State: Equatable {
    static func == (lhs: LightStore.State, rhs: LightStore.State) -> Bool {
        switch (lhs, rhs) {
        case let (
            .featureIsIdle(lhsUniqueId, lhsDescriptor),
            .featureIsIdle(rhsUniqueId, rhsDescriptor)
        ):
            return lhsUniqueId == rhsUniqueId && lhsDescriptor == rhsDescriptor

        case let (
            .featureIsStarted(lhsUniqueId, lhsDescriptor),
            .featureIsStarted(rhsUniqueId, rhsDescriptor)
        ):
            return lhsUniqueId == rhsUniqueId && lhsDescriptor == rhsDescriptor

        case let (
            .lightIsChangingInApp(
                lhsUniqueId,
                lhsDescriptor,
                lhsExpectedDescriptor,
                lhsSuppressedIncomingDescriptor,
                _
            ),
            .lightIsChangingInApp(
                rhsUniqueId,
                rhsDescriptor,
                rhsExpectedDescriptor,
                rhsSuppressedIncomingDescriptor,
                _
            )
        ):
            return lhsUniqueId == rhsUniqueId
                && lhsDescriptor == rhsDescriptor
                && lhsExpectedDescriptor == rhsExpectedDescriptor
                && lhsSuppressedIncomingDescriptor == rhsSuppressedIncomingDescriptor

        default:
            return false
        }
    }
}

extension LightStore.Event: Equatable {
    static func == (lhs: LightStore.Event, rhs: LightStore.Event) -> Bool {
        switch (lhs, rhs) {
        case let (.powerWasSetInApp(lhsIsOn), .powerWasSetInApp(rhsIsOn)):
            return lhsIsOn == rhsIsOn

        case let (
            .levelNormalizedWasSetInApp(lhsNormalizedLevel),
            .levelNormalizedWasSetInApp(rhsNormalizedLevel)
        ):
            return lhsNormalizedLevel == rhsNormalizedLevel

        case let (.descriptorWasReceived(lhsDescriptor), .descriptorWasReceived(rhsDescriptor)):
            return lhsDescriptor == rhsDescriptor

        case (.timeoutHasExpired, .timeoutHasExpired):
            return true

        case (.timeoutTaskWasCreated, .timeoutTaskWasCreated):
            // Task identity is intentionally ignored in event equality.
            return true

        default:
            return false
        }
    }
}

extension LightStore.Effect: Equatable {
    static func == (lhs: LightStore.Effect, rhs: LightStore.Effect) -> Bool {
        switch (lhs, rhs) {
        case (.cancelTimeout(task: _), .cancelTimeout(task: _)):
            // Task identity is intentionally ignored in effect equality.
            return true

        case let (
            .sendControlChanges(lhsUniqueId, lhsChanges),
            .sendControlChanges(rhsUniqueId, rhsChanges)
        ):
            return lhsUniqueId == rhsUniqueId && lhsChanges == rhsChanges

        case (.startTimeout, .startTimeout):
            return true

        default:
            return false
        }
    }
}
