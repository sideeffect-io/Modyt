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
        let intValue = Int(snapped)
        switch intValue {
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
    private(set) var descriptor: DeviceControlDescriptor
    private(set) var actualStep: ShutterStep
    private(set) var targetStep: ShutterStep?

    private var hasSnapshot = false
    private let onCommand: (String, JSONValue) -> Void
    private var observationTask: Task<Void, Never>?

    var effectiveTargetStep: ShutterStep {
        targetStep ?? actualStep
    }

    var isInFlight: Bool {
        guard let targetStep else { return false }
        return actualStep != targetStep
    }

    init(
        device: DeviceRecord,
        shutterRepository: ShutterRepository,
        onCommand: @escaping (String, JSONValue) -> Void
    ) {
        let resolvedDescriptor = Self.sliderDescriptor(for: device) ?? DeviceControlDescriptor(
            kind: .slider,
            key: "level",
            isOn: false,
            value: 0,
            range: 0...100
        )

        self.descriptor = resolvedDescriptor
        self.actualStep = ShutterStep.nearestStep(for: resolvedDescriptor.value, in: resolvedDescriptor.range)
        self.targetStep = nil
        self.onCommand = onCommand

        let uniqueId = device.uniqueId
        observationTask = Task { [weak self] in
            let stream = await shutterRepository.observeShutter(uniqueId: uniqueId)
            for await snapshot in stream {
                guard let snapshot else { continue }
                guard snapshot.uniqueId == uniqueId else { continue }
                self?.apply(snapshot: snapshot)
            }
        }
    }

    @MainActor
    deinit {
        observationTask?.cancel()
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

        let targetValue = step.mappedValue(in: descriptor.range)
        onCommand(descriptor.key, .number(targetValue))
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
