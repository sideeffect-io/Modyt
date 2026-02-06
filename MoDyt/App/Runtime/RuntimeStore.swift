import Foundation
import Observation
import DeltaDoreClient

struct DeviceGroupSection: Sendable, Equatable, Identifiable {
    let group: DeviceGroup
    let devices: [DeviceRecord]

    var id: DeviceGroup { group }
}

struct RuntimeState: Sendable, Equatable {
    var devices: [DeviceRecord]
    var groupedDevices: [DeviceGroupSection]
    var favorites: [DeviceRecord]
    var isAppActive: Bool

    static let initial = RuntimeState(
        devices: [],
        groupedDevices: [],
        favorites: [],
        isAppActive: true
    )
}

private func deriveDeviceCollections(
    from devices: [DeviceRecord]
) -> (grouped: [DeviceGroupSection], favorites: [DeviceRecord]) {
    let grouped = Dictionary(grouping: devices, by: { $0.group })
    let groupedDevices = DeviceGroup.allCases.compactMap { group -> DeviceGroupSection? in
        guard let devices = grouped[group] else { return nil }
        let sorted = devices.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return DeviceGroupSection(group: group, devices: sorted)
    }
    let favorites = devices
        .filter { $0.isFavorite }
        .sorted { ($0.dashboardOrder ?? Int.max) < ($1.dashboardOrder ?? Int.max) }
    return (groupedDevices, favorites)
}

enum RuntimeEvent: Sendable {
    case onStart
    case devicesUpdated([DeviceRecord])
    case setAppActive(Bool)
    case refreshRequested
    case toggleFavorite(String)
    case reorderFavorite(String, String)
    case deviceControlChanged(uniqueId: String, key: String, value: JSONValue)
    case disconnectTapped
    case disconnected
}

enum RuntimeEffect: Sendable, Equatable {
    case preparePersistence
    case startObservingDevices
    case startMessageStream
    case sendBootstrapRequests
    case sendRefreshAll
    case setAppActive(Bool)
    case applyOptimisticUpdate(uniqueId: String, key: String, value: JSONValue)
    case sendDeviceCommand(uniqueId: String, key: String, value: JSONValue)
    case toggleFavorite(String)
    case reorderFavorite(from: String, to: String)
    case disconnectAndClearStoredData
}

enum RuntimeDelegateEvent {
    case didDisconnect
}

enum RuntimeReducer {
    static func reduce(
        state: RuntimeState,
        event: RuntimeEvent
    ) -> (RuntimeState, [RuntimeEffect]) {
        var state = state
        var effects: [RuntimeEffect] = []

        switch event {
        case .onStart:
            effects = [.preparePersistence, .startObservingDevices, .startMessageStream, .sendBootstrapRequests, .setAppActive(state.isAppActive)]

        case .devicesUpdated(let devices):
            state.devices = devices
            let derived = deriveDeviceCollections(from: devices)
            state.groupedDevices = derived.grouped
            state.favorites = derived.favorites

        case .setAppActive(let isActive):
            state.isAppActive = isActive
            effects = [.setAppActive(isActive)]

        case .refreshRequested:
            effects = [.sendRefreshAll]

        case .toggleFavorite(let uniqueId):
            effects = [.toggleFavorite(uniqueId)]

        case .reorderFavorite(let fromId, let toId):
            effects = [.reorderFavorite(from: fromId, to: toId)]

        case .deviceControlChanged(let uniqueId, let key, let value):
            let isShutterSliderControl = state.devices.first(where: { $0.uniqueId == uniqueId })
                .flatMap { device -> DeviceControlDescriptor? in
                    guard device.group == .shutter else { return nil }
                    guard let descriptor = device.primaryControlDescriptor(), descriptor.kind == .slider else { return nil }
                    return descriptor.key == key ? descriptor : nil
                } != nil

            if isShutterSliderControl {
                effects = [
                    .sendDeviceCommand(uniqueId: uniqueId, key: key, value: value)
                ]
            } else {
                effects = [
                    .applyOptimisticUpdate(uniqueId: uniqueId, key: key, value: value),
                    .sendDeviceCommand(uniqueId: uniqueId, key: key, value: value)
                ]
            }

        case .disconnectTapped:
            state.devices = []
            state.groupedDevices = []
            state.favorites = []
            effects = [.disconnectAndClearStoredData]

        case .disconnected:
            break
        }

        return (state, effects)
    }
}

@Observable
@MainActor
final class RuntimeStore {
    private(set) var state: RuntimeState

    var shutterRepository: ShutterRepository { environment.shutterRepository }
    var onDelegateEvent: @MainActor (RuntimeDelegateEvent) -> Void

    private let environment: AppEnvironment
    private var connection: TydomConnection?
    private var messageTask: Task<Void, Never>?
    private var deviceObserverTask: Task<Void, Never>?

    init(
        environment: AppEnvironment,
        connection: TydomConnection,
        onDelegateEvent: @escaping @MainActor (RuntimeDelegateEvent) -> Void = { _ in }
    ) {
        self.environment = environment
        self.connection = connection
        self.state = .initial
        self.onDelegateEvent = onDelegateEvent
    }

    func send(_ event: RuntimeEvent) {
        let (next, effects) = RuntimeReducer.reduce(state: state, event: event)
        state = next

        switch event {
        case .disconnected:
            onDelegateEvent(.didDisconnect)
        default:
            break
        }

        handle(effects)
    }

    private func handle(_ effects: [RuntimeEffect]) {
        for effect in effects {
            handle(effect)
        }
    }

    private func handle(_ effect: RuntimeEffect) {
        switch effect {
        case .preparePersistence:
            Task { [environment] in
                try? await environment.repository.startIfNeeded()
                try? await environment.shutterRepository.startIfNeeded()
            }

        case .startObservingDevices:
            guard deviceObserverTask == nil else { return }
            deviceObserverTask = Task { [environment] in
                let stream = await environment.repository.observeDevices()
                for await devices in stream {
                    await MainActor.run {
                        self.send(.devicesUpdated(devices))
                    }
                }
            }

        case .startMessageStream:
            guard messageTask == nil else { return }
            guard let connection else { return }
            messageTask = Task { [environment] in
                environment.log("Message stream started")
                let messages = await connection.decodedMessages(logger: environment.log)
                for await message in messages {
                    environment.log("Message received \(describe(message))")
                    await environment.repository.applyMessage(message)
                }
                environment.log("Message stream finished")
            }

        case .sendBootstrapRequests:
            Task { [weak self] in
                guard let self, let connection = self.connection else { return }
                self.environment.log("Send configs-file")
                try? await connection.send(text: TydomCommand.configsFile().request)
                self.environment.log("Send devices-meta")
                try? await connection.send(text: TydomCommand.devicesMeta().request)
                self.environment.log("Send devices-cmeta")
                try? await connection.send(text: TydomCommand.devicesCmeta().request)
                self.environment.log("Send devices-data")
                try? await connection.send(text: TydomCommand.devicesData().request)
                self.environment.log("Send refresh-all")
                try? await connection.send(text: TydomCommand.refreshAll().request)
            }

        case .sendRefreshAll:
            Task { [weak self] in
                guard let self, let connection = self.connection else { return }
                self.environment.log("Send refresh-all")
                try? await connection.send(text: TydomCommand.refreshAll().request)
            }

        case .setAppActive(let isActive):
            Task { [weak self] in
                guard let self, let connection = self.connection else { return }
                await connection.setAppActive(isActive)
            }

        case .applyOptimisticUpdate(let uniqueId, let key, let value):
            Task { [environment] in
                await environment.repository.applyOptimisticUpdate(uniqueId: uniqueId, key: key, value: value)
            }

        case .sendDeviceCommand(let uniqueId, let key, let value):
            Task { [weak self] in
                guard let self,
                      let connection = self.connection,
                      let device = self.state.devices.first(where: { $0.uniqueId == uniqueId }) else { return }

                if device.group == .shutter,
                   let descriptor = device.primaryControlDescriptor(),
                   descriptor.kind == .slider,
                   descriptor.key == key,
                   let numberValue = value.numberValue {
                    let targetStep = ShutterStep.nearestStep(for: numberValue, in: descriptor.range)
                    let originStep = ShutterStep.nearestStep(for: descriptor.value, in: descriptor.range)
                    await self.environment.shutterRepository.setTarget(
                        uniqueId: uniqueId,
                        targetStep: targetStep,
                        originStep: originStep
                    )
                }

                let commandValue = deviceCommandValue(from: value)
                let command = TydomCommand.putDevicesData(
                    deviceId: String(device.deviceId),
                    endpointId: String(device.endpointId),
                    name: key,
                    value: commandValue
                )
                try? await connection.send(text: command.request)
            }

        case .toggleFavorite(let uniqueId):
            Task { [environment] in
                await environment.repository.toggleFavorite(uniqueId: uniqueId)
            }

        case .reorderFavorite(let fromId, let toId):
            Task { [environment] in
                await environment.repository.reorderDashboard(from: fromId, to: toId)
            }

        case .disconnectAndClearStoredData:
            Task { [weak self, environment] in
                guard let self else { return }
                await self.disconnect()
                await environment.shutterRepository.clearAll()
                await environment.client.clearStoredData()
                await MainActor.run {
                    self.send(.disconnected)
                }
            }
        }
    }

    private func disconnect() async {
        messageTask?.cancel()
        messageTask = nil
        deviceObserverTask?.cancel()
        deviceObserverTask = nil
        await connection?.disconnect()
        connection = nil
    }
}

private func describe(_ message: TydomMessage) -> String {
    switch message {
    case .devices(let devices, let transactionId):
        return "devices count=\(devices.count) tx=\(transactionId ?? "nil")"
    case .gatewayInfo(_, let transactionId):
        return "gatewayInfo tx=\(transactionId ?? "nil")"
    case .scenarios(let scenarios, let transactionId):
        return "scenarios count=\(scenarios.count) tx=\(transactionId ?? "nil")"
    case .groups(_, let transactionId):
        return "groups tx=\(transactionId ?? "nil")"
    case .moments(_, let transactionId):
        return "moments tx=\(transactionId ?? "nil")"
    case .areas(let areas, let transactionId):
        return "areas count=\(areas.count) tx=\(transactionId ?? "nil")"
    case .raw(let raw):
        let origin = raw.uriOrigin ?? "nil"
        let tx = raw.transactionId ?? "nil"
        let bodyCount = raw.frame?.body?.count ?? 0
        let preview = raw.frame?.body
            .flatMap { data in
                String(data: data.prefix(200), encoding: .isoLatin1)
                    ?? String(decoding: data.prefix(200), as: UTF8.self)
            } ?? ""
        let suffix = preview.isEmpty ? "" : " bodyPreview=\(preview)"
        return "raw bytes=\(raw.payload.count) uri=\(origin) tx=\(tx) body=\(bodyCount)\(suffix)"
    }
}

private func deviceCommandValue(from value: JSONValue) -> TydomCommand.DeviceDataValue {
    switch value {
    case .bool(let flag):
        return .bool(flag)
    case .number(let number):
        return .int(Int(number.rounded()))
    case .string(let text):
        return .string(text)
    case .null, .object, .array:
        return .null
    }
}
