import Foundation
import Observation
import DeltaDoreClient

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

    func mappedValue(in range: ClosedRange<Double>) -> Double {
        guard range.upperBound > range.lowerBound else { return range.lowerBound }
        let normalized = Double(rawValue) / 100
        return range.lowerBound + (range.upperBound - range.lowerBound) * normalized
    }

    static func nearestStep(for value: Double, in range: ClosedRange<Double>) -> ShutterStep {
        guard range.upperBound > range.lowerBound else { return .closed }
        let normalized = ((value - range.lowerBound) / (range.upperBound - range.lowerBound)) * 100
        let clamped = min(max(normalized, 0), 100)
        let snapped = (clamped / 25).rounded() * 25
        switch Int(snapped) {
        case 100: return .open
        case 75: return .threeQuarter
        case 50: return .half
        case 25: return .quarter
        default: return .closed
        }
    }
}

@Observable
@MainActor
final class ShutterStore {
    struct Dependencies {
        let observeShutter: (String) async -> AsyncStream<ShutterSnapshot?>
        let setTarget: (String, ShutterStep, ShutterStep) async -> Void
        let sendCommand: (String, String, JSONValue) async -> Void
    }

    private(set) var descriptor: DeviceControlDescriptor
    private(set) var actualStep: ShutterStep
    private(set) var targetStep: ShutterStep?

    private var hasSnapshot = false
    private let uniqueId: String
    private let dependencies: Dependencies
    private let observationTask = TaskHandle()

    var effectiveTargetStep: ShutterStep {
        targetStep ?? actualStep
    }

    var isInFlight: Bool {
        guard let targetStep else { return false }
        return actualStep != targetStep
    }

    init(
        uniqueId: String,
        initialDevice: DeviceRecord?,
        dependencies: Dependencies
    ) {
        let resolvedDescriptor = initialDevice
            .flatMap(Self.sliderDescriptor(for:))
            ?? DeviceControlDescriptor(
                kind: .slider,
                key: "level",
                isOn: false,
                value: 0,
                range: 0...100
            )

        self.uniqueId = uniqueId
        self.dependencies = dependencies
        self.descriptor = resolvedDescriptor
        self.actualStep = ShutterStep.nearestStep(for: resolvedDescriptor.value, in: resolvedDescriptor.range)
        self.targetStep = nil

        observationTask.task = Task { [weak self, dependencies] in
            let stream = await dependencies.observeShutter(uniqueId)
            for await snapshot in stream {
                guard let snapshot else { continue }
                guard snapshot.uniqueId == uniqueId else { continue }
                self?.apply(snapshot: snapshot)
            }
        }
    }

    func sync(device: DeviceRecord) {
        guard let descriptor = Self.sliderDescriptor(for: device) else { return }
        self.descriptor = descriptor
        if !hasSnapshot {
            actualStep = ShutterStep.nearestStep(for: descriptor.value, in: descriptor.range)
        }
    }

    func select(_ step: ShutterStep) {
        guard step != actualStep else { return }

        targetStep = step

        let originStep = actualStep
        let descriptorKey = descriptor.key
        let targetValue = step.mappedValue(in: descriptor.range)

        Task { [dependencies, uniqueId] in
            await dependencies.setTarget(uniqueId, step, originStep)
            await dependencies.sendCommand(uniqueId, descriptorKey, .number(targetValue))
        }
    }

    private static func sliderDescriptor(for device: DeviceRecord) -> DeviceControlDescriptor? {
        guard device.group == .shutter else { return nil }
        guard let descriptor = device.primaryControlDescriptor(), descriptor.kind == .slider else { return nil }
        return descriptor
    }

    private func apply(snapshot: ShutterSnapshot) {
        hasSnapshot = true
        descriptor = snapshot.descriptor
        actualStep = snapshot.actualStep
        targetStep = snapshot.targetStep
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
