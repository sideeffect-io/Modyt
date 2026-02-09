import Foundation
import Observation
import DeltaDoreClient

@Observable
@MainActor
final class LightStore {
    struct Dependencies {
        let observeLight: (String) async -> AsyncStream<DeviceRecord?>
        let applyOptimisticUpdate: (String, String, JSONValue) async -> Void
        let sendCommand: (String, String, JSONValue) async -> Void
    }

    private(set) var descriptor: DrivingLightControlDescriptor

    private let uniqueId: String
    private let dependencies: Dependencies
    private let observationTask = TaskHandle()

    init(
        uniqueId: String,
        initialDevice: DeviceRecord?,
        dependencies: Dependencies
    ) {
        self.uniqueId = uniqueId
        self.dependencies = dependencies
        self.descriptor = initialDevice?.drivingLightControlDescriptor() ?? Self.fallbackDescriptor

        observationTask.task = Task { [weak self, dependencies] in
            let stream = await dependencies.observeLight(uniqueId)
            for await device in stream {
                guard let device else { continue }
                guard device.uniqueId == uniqueId else { continue }
                self?.apply(device)
            }
        }
    }

    func setPower(_ isOn: Bool) {
        guard descriptor.isOn != isOn else { return }

        if let powerKey = descriptor.powerKey {
            applyLocalPower(isOn)
            sendControlChange(key: powerKey, value: .bool(isOn))
            return
        }

        guard let levelKey = descriptor.levelKey else { return }
        let targetLevel = isOn ? descriptor.range.upperBound : descriptor.range.lowerBound
        applyLocalLevel(targetLevel)
        sendControlChange(key: levelKey, value: .number(targetLevel))
    }

    func setLevelNormalized(_ normalized: Double) {
        let clamped = min(max(normalized, 0), 1)

        guard let levelKey = descriptor.levelKey else {
            guard let powerKey = descriptor.powerKey else { return }
            let shouldBeOn = clamped > 0.01
            guard descriptor.isOn != shouldBeOn else { return }
            applyLocalPower(shouldBeOn)
            sendControlChange(key: powerKey, value: .bool(shouldBeOn))
            return
        }

        let targetLevel = descriptor.range.lowerBound
            + (descriptor.range.upperBound - descriptor.range.lowerBound) * clamped
        let previousIsOn = descriptor.isOn
        applyLocalLevel(targetLevel)
        sendControlChange(key: levelKey, value: .number(targetLevel))

        if let powerKey = descriptor.powerKey, descriptor.isOn != previousIsOn {
            sendControlChange(key: powerKey, value: .bool(descriptor.isOn))
        }
    }

    private func applyLocalPower(_ isOn: Bool) {
        let fallbackLevel = isOn ? descriptor.range.upperBound : descriptor.range.lowerBound
        let nextLevel = descriptor.levelKey == nil ? fallbackLevel : descriptor.level
        descriptor = DrivingLightControlDescriptor(
            powerKey: descriptor.powerKey,
            levelKey: descriptor.levelKey,
            isOn: isOn,
            level: nextLevel,
            range: descriptor.range
        )
    }

    private func applyLocalLevel(_ rawLevel: Double) {
        let clampedLevel = min(max(rawLevel, descriptor.range.lowerBound), descriptor.range.upperBound)
        descriptor = DrivingLightControlDescriptor(
            powerKey: descriptor.powerKey,
            levelKey: descriptor.levelKey,
            isOn: clampedLevel > descriptor.range.lowerBound,
            level: clampedLevel,
            range: descriptor.range
        )
    }

    private func sendControlChange(key: String, value: JSONValue) {
        Task { [dependencies, uniqueId] in
            await dependencies.applyOptimisticUpdate(uniqueId, key, value)
            await dependencies.sendCommand(uniqueId, key, value)
        }
    }

    private func apply(_ device: DeviceRecord) {
        guard let descriptor = device.drivingLightControlDescriptor() else { return }
        self.descriptor = descriptor
    }

    private static let fallbackDescriptor = DrivingLightControlDescriptor(
        powerKey: "on",
        levelKey: nil,
        isOn: false,
        level: 0,
        range: 0...100
    )
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
