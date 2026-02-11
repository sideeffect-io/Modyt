import Foundation
import Observation
import DeltaDoreClient

@Observable
@MainActor
final class HeatPumpStore {
    struct Dependencies {
        let observeHeatPump: @Sendable (String) async -> any AsyncSequence<DeviceRecord?, Never> & Sendable
        let applyOptimisticChanges: @Sendable (String, [String: JSONValue]) async -> Void
        let sendCommand: @Sendable (String, String, JSONValue) async -> Void
        let now: () -> Date

        init(
            observeHeatPump: @escaping @Sendable (String) async -> any AsyncSequence<DeviceRecord?, Never> & Sendable,
            applyOptimisticChanges: @escaping @Sendable (String, [String: JSONValue]) async -> Void,
            sendCommand: @escaping @Sendable (String, String, JSONValue) async -> Void,
            now: @escaping () -> Date = Date.init
        ) {
            self.observeHeatPump = observeHeatPump
            self.applyOptimisticChanges = applyOptimisticChanges
            self.sendCommand = sendCommand
            self.now = now
        }
    }

    private(set) var descriptor: ThermostatDescriptor?

    private let uniqueId: String
    private let dependencies: Dependencies
    private let observationTask = TaskHandle()
    private let worker: Worker
    private var pendingSetpoint: Double?
    private var pendingSetpointExpiresAt: Date?

    init(
        uniqueId: String,
        initialDevice: DeviceRecord? = nil,
        dependencies: Dependencies
    ) {
        self.uniqueId = uniqueId
        self.dependencies = dependencies
        self.descriptor = initialDevice?.thermostatDescriptor()
        self.worker = Worker(
            uniqueId: uniqueId,
            observeHeatPump: dependencies.observeHeatPump,
            applyOptimisticChanges: dependencies.applyOptimisticChanges,
            sendCommand: dependencies.sendCommand
        )

        observationTask.task = Task { [weak self, worker] in
            await worker.observe { [weak self] descriptor in
                await self?.applyIncomingDescriptor(descriptor)
            }
        }
    }

    func incrementSetpoint() {
        adjustSetpoint(by: +1)
    }

    func decrementSetpoint() {
        adjustSetpoint(by: -1)
    }

    func setSetpoint(_ target: Double) {
        guard var descriptor else { return }
        guard descriptor.canAdjustSetpoint else { return }
        guard let setpointKey = descriptor.setpointKey else { return }
        guard let current = descriptor.setpoint else { return }

        let step = max(descriptor.setpointStep, Self.defaultSetpointStep)
        let resolved = Self.resolveSetpoint(
            target,
            in: descriptor.setpointRange,
            step: step
        )

        guard abs(resolved - current) > Self.setpointTolerance else { return }

        descriptor = ThermostatDescriptor(
            temperature: descriptor.temperature,
            humidity: descriptor.humidity,
            setpointKey: descriptor.setpointKey,
            setpoint: resolved,
            setpointRange: descriptor.setpointRange,
            setpointStep: descriptor.setpointStep,
            unitSymbol: descriptor.unitSymbol
        )
        self.descriptor = descriptor
        registerPendingSetpoint(resolved)

        let commandValue = Self.commandValue(for: resolved, step: step)
        Task { [worker, setpointKey] in
            await worker.sendSetpoint(setpointKey, value: commandValue)
        }
    }

    private func adjustSetpoint(by direction: Double) {
        guard let descriptor else { return }
        let base = descriptor.setpoint ?? descriptor.setpointRange.lowerBound
        let step = max(descriptor.setpointStep, Self.defaultSetpointStep)
        setSetpoint(base + direction * step)
    }

    private func applyIncomingDescriptor(_ descriptor: ThermostatDescriptor?) {
        guard !shouldSuppressIncoming(descriptor) else { return }
        guard self.descriptor != descriptor else { return }
        self.descriptor = descriptor
    }

    private func shouldSuppressIncoming(_ incoming: ThermostatDescriptor?) -> Bool {
        guard let pendingSetpoint else { return false }
        guard let incoming else {
            clearPendingSetpoint()
            return false
        }
        guard let incomingSetpoint = incoming.setpoint else {
            clearPendingSetpoint()
            return false
        }

        if abs(incomingSetpoint - pendingSetpoint) <= Self.setpointTolerance {
            clearPendingSetpoint()
            return false
        }

        if let pendingSetpointExpiresAt, dependencies.now() < pendingSetpointExpiresAt {
            return true
        }

        clearPendingSetpoint()
        return false
    }

    private func registerPendingSetpoint(_ value: Double) {
        pendingSetpoint = value
        pendingSetpointExpiresAt = dependencies.now().addingTimeInterval(Self.pendingEchoSuppressionWindow)
    }

    private func clearPendingSetpoint() {
        pendingSetpoint = nil
        pendingSetpointExpiresAt = nil
    }

    private static func resolveSetpoint(
        _ value: Double,
        in range: ClosedRange<Double>,
        step: Double
    ) -> Double {
        guard range.upperBound > range.lowerBound else { return range.lowerBound }
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        guard step > 0 else { return clamped }

        let stepsFromLowerBound = ((clamped - range.lowerBound) / step).rounded()
        let snapped = range.lowerBound + stepsFromLowerBound * step
        let bounded = min(max(snapped, range.lowerBound), range.upperBound)

        let digits = max(2, fractionDigits(for: step))
        let factor = pow(10.0, Double(digits))
        return (bounded * factor).rounded() / factor
    }

    private static func commandValue(for value: Double, step: Double) -> JSONValue {
        let digits = fractionDigits(for: step)
        let commandText = formattedSetpoint(value, digits: digits)
        return .string(commandText)
    }

    private static func fractionDigits(for step: Double) -> Int {
        guard step > 0 else { return 1 }
        var digits = 0
        var scaled = step
        while digits < 4 && abs(scaled.rounded() - scaled) > 0.000_001 {
            scaled *= 10
            digits += 1
        }
        return digits
    }

    private static func formattedSetpoint(_ value: Double, digits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = max(digits, 1)
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private static let defaultSetpointStep = 0.5
    private static let setpointTolerance = 0.000_5
    private static let pendingEchoSuppressionWindow: TimeInterval = 0.9

    private actor Worker {
        private let uniqueId: String
        private let observeHeatPump: @Sendable (String) async -> any AsyncSequence<DeviceRecord?, Never> & Sendable
        private let applyOptimisticChanges: @Sendable (String, [String: JSONValue]) async -> Void
        private let sendCommand: @Sendable (String, String, JSONValue) async -> Void

        init(
            uniqueId: String,
            observeHeatPump: @escaping @Sendable (String) async -> any AsyncSequence<DeviceRecord?, Never> & Sendable,
            applyOptimisticChanges: @escaping @Sendable (String, [String: JSONValue]) async -> Void,
            sendCommand: @escaping @Sendable (String, String, JSONValue) async -> Void
        ) {
            self.uniqueId = uniqueId
            self.observeHeatPump = observeHeatPump
            self.applyOptimisticChanges = applyOptimisticChanges
            self.sendCommand = sendCommand
        }

        func observe(
            onDescriptor: @escaping @Sendable (ThermostatDescriptor?) async -> Void
        ) async {
            let stream = await observeHeatPump(uniqueId)
            for await device in stream {
                guard !Task.isCancelled else { return }
                if let device, device.uniqueId != uniqueId {
                    continue
                }
                await onDescriptor(device?.thermostatDescriptor())
            }
        }

        func sendSetpoint(_ key: String, value: JSONValue) async {
            await applyOptimisticChanges(uniqueId, [key: value])
            await sendCommand(uniqueId, key, value)
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
