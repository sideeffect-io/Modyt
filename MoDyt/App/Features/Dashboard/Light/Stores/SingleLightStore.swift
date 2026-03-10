import Foundation
import Observation

struct SingleLightPendingPresentation: Sendable, Equatable {
    let normalizedLevel: Double
    let isOn: Bool
}

struct SingleLightPendingCommand: Sendable, Equatable {
    let request: LightGatewayCommandRequest
    let presentation: SingleLightPendingPresentation
    let expectedPowerState: Bool?
    let expectedLevel: Int?

    func matches(_ descriptor: DrivingLightControlDescriptor?) -> Bool {
        guard let descriptor else { return false }

        if let expectedPowerState, descriptor.isOn != expectedPowerState {
            return false
        }

        if let expectedLevel,
           Int(descriptor.level.rounded()) != expectedLevel {
            return false
        }

        return true
    }
}

enum SingleLightState: Sendable, Equatable {
    case featureIsIdle(deviceId: DeviceIdentifier, descriptor: DrivingLightControlDescriptor?)
    case featureIsStarted(deviceId: DeviceIdentifier, descriptor: DrivingLightControlDescriptor?)
    case commandIsPending(
        deviceId: DeviceIdentifier,
        descriptor: DrivingLightControlDescriptor?,
        pendingCommand: SingleLightPendingCommand
    )

    var deviceId: DeviceIdentifier {
        switch self {
        case .featureIsIdle(let deviceId, _),
             .featureIsStarted(let deviceId, _),
             .commandIsPending(let deviceId, _, _):
            return deviceId
        }
    }

    var descriptor: DrivingLightControlDescriptor? {
        switch self {
        case .featureIsIdle(_, let descriptor),
             .featureIsStarted(_, let descriptor),
             .commandIsPending(_, let descriptor, _):
            return descriptor
        }
    }

    var pendingCommand: SingleLightPendingCommand? {
        guard case .commandIsPending(_, _, let pendingCommand) = self else { return nil }
        return pendingCommand
    }

    var displayedNormalizedLevel: Double {
        pendingCommand?.presentation.normalizedLevel
            ?? descriptor?.normalizedLevel
            ?? 0
    }

    var displayedIsOn: Bool {
        pendingCommand?.presentation.isOn
            ?? descriptor?.isOn
            ?? false
    }
}

enum SingleLightEvent: Sendable, Equatable {
    case descriptorWasReceived(DrivingLightControlDescriptor?)
    case levelWasCommitted(Double)
    case powerWasSet(Bool)
}

enum SingleLightEffect: Sendable, Equatable {
    case sendCommand(LightGatewayCommandRequest)
}

@Observable
@MainActor
final class SingleLightStore: StartableStore {
    struct StateMachine {
        var state: SingleLightState

        mutating func reduce(_ event: SingleLightEvent) -> [SingleLightEffect] {
            switch (state, event) {
            case let (.featureIsIdle(deviceId, _), .descriptorWasReceived(descriptor)):
                state = .featureIsStarted(deviceId: deviceId, descriptor: descriptor)
                return []

            case let (.featureIsStarted(deviceId, _), .descriptorWasReceived(descriptor)):
                state = .featureIsStarted(deviceId: deviceId, descriptor: descriptor)
                return []

            case let (.commandIsPending(deviceId, _, pendingCommand), .descriptorWasReceived(descriptor)):
                if pendingCommand.matches(descriptor) {
                    state = .featureIsStarted(deviceId: deviceId, descriptor: descriptor)
                } else {
                    state = .commandIsPending(
                        deviceId: deviceId,
                        descriptor: descriptor,
                        pendingCommand: pendingCommand
                    )
                }
                return []

            case let (.featureIsStarted(deviceId, descriptor), .levelWasCommitted(normalizedLevel)),
                 let (.commandIsPending(deviceId, descriptor, _), .levelWasCommitted(normalizedLevel)):
                return setLevel(
                    deviceId: deviceId,
                    descriptor: descriptor,
                    normalizedLevel: normalizedLevel
                )

            case let (.featureIsStarted(deviceId, descriptor), .powerWasSet(isOn)),
                 let (.commandIsPending(deviceId, descriptor, _), .powerWasSet(isOn)):
                return setPower(
                    deviceId: deviceId,
                    descriptor: descriptor,
                    isOn: isOn
                )

            default:
                return []
            }
        }

        private mutating func setLevel(
            deviceId: DeviceIdentifier,
            descriptor: DrivingLightControlDescriptor?,
            normalizedLevel: Double
        ) -> [SingleLightEffect] {
            guard let descriptor,
                  let levelKey = descriptor.levelKey else { return [] }

            let rawLevel = descriptor.rawLevel(forNormalizedLevel: normalizedLevel)
            let request = LightGatewayCommandRequest(
                deviceId: deviceId,
                signalName: levelKey,
                value: .int(rawLevel)
            )
            let pendingCommand = SingleLightPendingCommand(
                request: request,
                presentation: .init(
                    normalizedLevel: descriptor.normalizedLevel(forRawLevel: rawLevel),
                    isOn: descriptor.powerKey == nil ? descriptor.isLit(level: rawLevel) : descriptor.isOn
                ),
                expectedPowerState: nil,
                expectedLevel: rawLevel
            )
            state = .commandIsPending(
                deviceId: deviceId,
                descriptor: descriptor,
                pendingCommand: pendingCommand
            )
            return [.sendCommand(request)]
        }

        private mutating func setPower(
            deviceId: DeviceIdentifier,
            descriptor: DrivingLightControlDescriptor?,
            isOn: Bool
        ) -> [SingleLightEffect] {
            guard let descriptor else { return [] }

            if let powerKey = descriptor.powerKey {
                let request = LightGatewayCommandRequest(
                    deviceId: deviceId,
                    signalName: powerKey,
                    value: .bool(isOn)
                )
                let pendingCommand = SingleLightPendingCommand(
                    request: request,
                    presentation: .init(
                        normalizedLevel: descriptor.normalizedLevel,
                        isOn: isOn
                    ),
                    expectedPowerState: isOn,
                    expectedLevel: nil
                )
                state = .commandIsPending(
                    deviceId: deviceId,
                    descriptor: descriptor,
                    pendingCommand: pendingCommand
                )
                return [.sendCommand(request)]
            }

            guard let levelKey = descriptor.levelKey else { return [] }

            let rawLevel = isOn ? descriptor.maximumLevel : descriptor.minimumLevel
            let request = LightGatewayCommandRequest(
                deviceId: deviceId,
                signalName: levelKey,
                value: .int(rawLevel)
            )
            let pendingCommand = SingleLightPendingCommand(
                request: request,
                presentation: .init(
                    normalizedLevel: descriptor.normalizedLevel(forRawLevel: rawLevel),
                    isOn: isOn
                ),
                expectedPowerState: nil,
                expectedLevel: rawLevel
            )
            state = .commandIsPending(
                deviceId: deviceId,
                descriptor: descriptor,
                pendingCommand: pendingCommand
            )
            return [.sendCommand(request)]
        }
    }

    struct Dependencies {
        let observeLight: @Sendable (DeviceIdentifier) async -> any AsyncSequence<Device?, Never> & Sendable
        let sendCommand: @Sendable (LightGatewayCommandRequest) async -> Void

        init(
            observeLight: @escaping @Sendable (DeviceIdentifier) async -> any AsyncSequence<Device?, Never> & Sendable,
            sendCommand: @escaping @Sendable (LightGatewayCommandRequest) async -> Void
        ) {
            self.observeLight = observeLight
            self.sendCommand = sendCommand
        }
    }

    private(set) var stateMachine: StateMachine

    var state: SingleLightState {
        stateMachine.state
    }

    var descriptor: DrivingLightControlDescriptor? {
        state.descriptor
    }

    var displayedNormalizedLevel: Double {
        state.displayedNormalizedLevel
    }

    var displayedIsOn: Bool {
        state.displayedIsOn
    }

    var isInteractionEnabled: Bool {
        descriptor != nil
    }

    private let observationTask = TaskHandle()
    private let worker: Worker
    private var hasStarted = false

    init(
        deviceId: DeviceIdentifier,
        dependencies: Dependencies
    ) {
        self.stateMachine = StateMachine(
            state: .featureIsIdle(deviceId: deviceId, descriptor: nil)
        )
        self.worker = Worker(
            observeLight: dependencies.observeLight,
            sendCommand: dependencies.sendCommand
        )
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        let deviceId = state.deviceId
        observationTask.task = Task { [weak self, worker] in
            await worker.observe(deviceId: deviceId) { [weak self] descriptor in
                await self?.send(.descriptorWasReceived(descriptor))
            }
        }
    }

    deinit {
        observationTask.cancel()
    }

    func send(_ event: SingleLightEvent) {
        let effects = stateMachine.reduce(event)
        handle(effects)
    }

    private func handle(_ effects: [SingleLightEffect]) {
        for effect in effects {
            switch effect {
            case .sendCommand(let request):
                Task { [worker] in
                    await worker.sendCommand(request)
                }
            }
        }
    }

    private actor Worker {
        private let observeLightSource: @Sendable (DeviceIdentifier) async -> any AsyncSequence<Device?, Never> & Sendable
        private let sendCommandAction: @Sendable (LightGatewayCommandRequest) async -> Void

        init(
            observeLight: @escaping @Sendable (DeviceIdentifier) async -> any AsyncSequence<Device?, Never> & Sendable,
            sendCommand: @escaping @Sendable (LightGatewayCommandRequest) async -> Void
        ) {
            self.observeLightSource = observeLight
            self.sendCommandAction = sendCommand
        }

        func observe(
            deviceId: DeviceIdentifier,
            onDescriptor: @escaping @Sendable (DrivingLightControlDescriptor?) async -> Void
        ) async {
            let stream = await observeLightSource(deviceId)
            var previousDescriptor: DrivingLightControlDescriptor?

            for await device in stream {
                guard !Task.isCancelled else { return }
                let descriptor = device?.drivingLightControlDescriptor()
                guard descriptor != previousDescriptor else { continue }
                await onDescriptor(descriptor)
                previousDescriptor = descriptor
            }
        }

        func sendCommand(_ request: LightGatewayCommandRequest) async {
            await sendCommandAction(request)
        }
    }
}
