import Foundation
import Observation
import DeltaDoreClient

@Observable
@MainActor
final class LightStore {
    private struct ControlChange: Sendable {
        let key: String
        let value: JSONValue
    }

    struct Dependencies {
        let observeLight: @Sendable (String) async -> any AsyncSequence<DeviceRecord?, Never> & Sendable
        let applyOptimisticChanges: @Sendable (String, [String: JSONValue]) async -> Void
        let sendCommand: @Sendable (String, String, JSONValue) async -> Void
        let now: () -> Date

        init(
            observeLight: @escaping @Sendable (String) async -> any AsyncSequence<DeviceRecord?, Never> & Sendable,
            applyOptimisticChanges: @escaping @Sendable (String, [String: JSONValue]) async -> Void,
            sendCommand: @escaping @Sendable (String, String, JSONValue) async -> Void,
            now: @escaping () -> Date = Date.init
        ) {
            self.observeLight = observeLight
            self.applyOptimisticChanges = applyOptimisticChanges
            self.sendCommand = sendCommand
            self.now = now
        }
    }

    private(set) var descriptor: DrivingLightControlDescriptor

    private let uniqueId: String
    private let dependencies: Dependencies
    private let observationTask = TaskHandle()
    private let worker: Worker
    private var pendingDescriptor: DrivingLightControlDescriptor?
    private var pendingDescriptorExpiresAt: Date?

    init(
        uniqueId: String,
        initialDevice: DeviceRecord? = nil,
        dependencies: Dependencies
    ) {
        self.uniqueId = uniqueId
        self.dependencies = dependencies
        self.descriptor = initialDevice?.drivingLightControlDescriptor() ?? Self.fallbackDescriptor
        self.worker = Worker(
            uniqueId: uniqueId,
            observeLight: dependencies.observeLight,
            applyOptimisticChanges: dependencies.applyOptimisticChanges,
            sendCommand: dependencies.sendCommand
        )

        observationTask.task = Task { [weak self, worker] in
            await worker.observe { [weak self] descriptor in
                await self?.applyIncomingDescriptor(descriptor)
            }
        }
    }

    func setPower(_ isOn: Bool) {
        guard descriptor.isOn != isOn else { return }

        if let powerKey = descriptor.powerKey {
            applyLocalPower(isOn)
            registerPendingDescriptor(descriptor)
            sendControlChanges([ControlChange(key: powerKey, value: .bool(isOn))])
            return
        }

        guard let levelKey = descriptor.levelKey else { return }
        let targetLevel = isOn ? descriptor.range.upperBound : descriptor.range.lowerBound
        applyLocalLevel(targetLevel)
        registerPendingDescriptor(descriptor)
        sendControlChanges([ControlChange(key: levelKey, value: .number(targetLevel))])
    }

    func setLevelNormalized(_ normalized: Double) {
        let clamped = min(max(normalized, 0), 1)

        guard let levelKey = descriptor.levelKey else {
            guard let powerKey = descriptor.powerKey else { return }
            let shouldBeOn = clamped > 0.01
            guard descriptor.isOn != shouldBeOn else { return }
            applyLocalPower(shouldBeOn)
            registerPendingDescriptor(descriptor)
            sendControlChanges([ControlChange(key: powerKey, value: .bool(shouldBeOn))])
            return
        }

        let targetLevel = descriptor.range.lowerBound
            + (descriptor.range.upperBound - descriptor.range.lowerBound) * clamped
        let previousDescriptor = descriptor
        let previousIsOn = descriptor.isOn
        applyLocalLevel(targetLevel)
        guard descriptor != previousDescriptor else { return }
        var controlChanges: [ControlChange] = [ControlChange(key: levelKey, value: .number(targetLevel))]
        if let powerKey = descriptor.powerKey, descriptor.isOn != previousIsOn {
            controlChanges.append(ControlChange(key: powerKey, value: .bool(descriptor.isOn)))
        }
        registerPendingDescriptor(descriptor)
        sendControlChanges(controlChanges)
    }

    private func applyLocalPower(_ isOn: Bool) {
        let fallbackLevel = isOn ? descriptor.range.upperBound : descriptor.range.lowerBound
        let nextLevel = descriptor.levelKey == nil ? fallbackLevel : descriptor.level
        let nextDescriptor = DrivingLightControlDescriptor(
            powerKey: descriptor.powerKey,
            levelKey: descriptor.levelKey,
            isOn: isOn,
            level: nextLevel,
            range: descriptor.range
        )
        guard descriptor != nextDescriptor else { return }
        descriptor = nextDescriptor
    }

    private func applyLocalLevel(_ rawLevel: Double) {
        let clampedLevel = min(max(rawLevel, descriptor.range.lowerBound), descriptor.range.upperBound)
        let nextDescriptor = DrivingLightControlDescriptor(
            powerKey: descriptor.powerKey,
            levelKey: descriptor.levelKey,
            isOn: clampedLevel > descriptor.range.lowerBound,
            level: clampedLevel,
            range: descriptor.range
        )
        guard descriptor != nextDescriptor else { return }
        descriptor = nextDescriptor
    }

    private func sendControlChanges(_ changes: [ControlChange]) {
        guard !changes.isEmpty else { return }
        Task { [worker, changes] in
            await worker.send(changes)
        }
    }

    private func applyIncomingDescriptor(_ descriptor: DrivingLightControlDescriptor) {
        guard !shouldSuppressIncoming(descriptor) else { return }
        guard self.descriptor != descriptor else { return }
        self.descriptor = descriptor
    }

    private func registerPendingDescriptor(_ descriptor: DrivingLightControlDescriptor) {
        pendingDescriptor = descriptor
        pendingDescriptorExpiresAt = dependencies.now().addingTimeInterval(Self.pendingEchoSuppressionWindow)
    }

    private func shouldSuppressIncoming(_ incoming: DrivingLightControlDescriptor) -> Bool {
        guard let pendingDescriptor else { return false }

        if matchesPendingDescriptor(incoming, pending: pendingDescriptor) {
            clearPendingDescriptor()
            return false
        }

        if let pendingDescriptorExpiresAt, dependencies.now() < pendingDescriptorExpiresAt {
            return true
        }

        clearPendingDescriptor()
        return false
    }

    private func clearPendingDescriptor() {
        pendingDescriptor = nil
        pendingDescriptorExpiresAt = nil
    }

    private func matchesPendingDescriptor(
        _ incoming: DrivingLightControlDescriptor,
        pending: DrivingLightControlDescriptor
    ) -> Bool {
        guard incoming.powerKey == pending.powerKey,
              incoming.levelKey == pending.levelKey,
              incoming.range == pending.range else {
            return false
        }

        let normalizedDelta = abs(incoming.normalizedLevel - pending.normalizedLevel)
        let levelMatches = normalizedDelta <= Self.pendingNormalizedTolerance || pending.levelKey == nil
        let powerMatches = incoming.powerKey == nil || incoming.isOn == pending.isOn
        return levelMatches && powerMatches
    }

    private static let pendingNormalizedTolerance: Double = 0.03
    private static let pendingEchoSuppressionWindow: TimeInterval = 0.9

    private static let fallbackDescriptor = DrivingLightControlDescriptor(
        powerKey: "on",
        levelKey: nil,
        isOn: false,
        level: 0,
        range: 0...100
    )

    private actor Worker {
        private let uniqueId: String
        private let observeLight: @Sendable (String) async -> any AsyncSequence<DeviceRecord?, Never> & Sendable
        private let applyOptimisticChanges: @Sendable (String, [String: JSONValue]) async -> Void
        private let sendCommand: @Sendable (String, String, JSONValue) async -> Void

        init(
            uniqueId: String,
            observeLight: @escaping @Sendable (String) async -> any AsyncSequence<DeviceRecord?, Never> & Sendable,
            applyOptimisticChanges: @escaping @Sendable (String, [String: JSONValue]) async -> Void,
            sendCommand: @escaping @Sendable (String, String, JSONValue) async -> Void
        ) {
            self.uniqueId = uniqueId
            self.observeLight = observeLight
            self.applyOptimisticChanges = applyOptimisticChanges
            self.sendCommand = sendCommand
        }

        func observe(
            onDescriptor: @escaping @Sendable (DrivingLightControlDescriptor) async -> Void
        ) async {
            let stream = await observeLight(uniqueId)
            for await device in stream {
                guard !Task.isCancelled else { return }
                guard let device else { continue }
                guard device.uniqueId == uniqueId else { continue }
                guard let descriptor = device.drivingLightControlDescriptor() else { continue }
                await onDescriptor(descriptor)
            }
        }

        func send(_ changes: [ControlChange]) async {
            guard !changes.isEmpty else { return }

            var optimisticChanges: [String: JSONValue] = [:]
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
