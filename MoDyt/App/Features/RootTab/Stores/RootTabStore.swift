import Foundation
import Observation
import DeltaDoreClient

struct RootTabState: Sendable, Equatable {
    var isAppActive: Bool

    static let initial = RootTabState(isAppActive: true)
}

enum RootTabEvent: Sendable {
    case onStart
    case setAppActive(Bool)
    case refreshRequested
    case disconnectRequested
    case disconnected
}

enum RootTabEffect: Sendable, Equatable {
    case preparePersistence
    case startMessageStream
    case sendBootstrapRequests
    case sendRefreshAll
    case setAppActive(Bool)
    case disconnectAndClearStoredData
}

enum RuntimeDelegateEvent {
    case didDisconnect
}

enum RootTabReducer {
    static func reduce(
        state: RootTabState,
        event: RootTabEvent
    ) -> (RootTabState, [RootTabEffect]) {
        var state = state
        var effects: [RootTabEffect] = []

        switch event {
        case .onStart:
            effects = [
                .preparePersistence,
                .startMessageStream,
                .sendBootstrapRequests,
                .setAppActive(state.isAppActive)
            ]

        case .setAppActive(let isActive):
            state.isAppActive = isActive
            effects = [.setAppActive(isActive)]

        case .refreshRequested:
            effects = [.sendRefreshAll]

        case .disconnectRequested:
            effects = [.disconnectAndClearStoredData]

        case .disconnected:
            break
        }

        return (state, effects)
    }
}

@Observable
@MainActor
final class RootTabStore {
    struct Dependencies {
        let log: (String) -> Void
        let preparePersistence: () async -> Void
        let decodeMessages: () async -> AsyncStream<TydomMessage>
        let applyMessage: (TydomMessage) async -> Void
        let sendText: (String) async -> Void
        let setAppActive: (Bool) async -> Void
        let disconnectConnection: () async -> Void
        let clearShutterState: () async -> Void
        let clearStoredData: () async -> Void
        let deviceByID: (String) async -> DeviceRecord?
    }

    private(set) var state: RootTabState

    var onDelegateEvent: @MainActor (RuntimeDelegateEvent) -> Void

    private let dependencies: Dependencies
    private let messageTask = TaskHandle()

    init(
        dependencies: Dependencies,
        onDelegateEvent: @escaping @MainActor (RuntimeDelegateEvent) -> Void = { _ in }
    ) {
        self.dependencies = dependencies
        self.state = .initial
        self.onDelegateEvent = onDelegateEvent
    }

    func send(_ event: RootTabEvent) {
        let (nextState, effects) = RootTabReducer.reduce(state: state, event: event)
        state = nextState

        if case .disconnected = event {
            onDelegateEvent(.didDisconnect)
        }

        handle(effects)
    }

    private func handle(_ effects: [RootTabEffect]) {
        for effect in effects {
            handle(effect)
        }
    }

    private func handle(_ effect: RootTabEffect) {
        switch effect {
        case .preparePersistence:
            Task { [dependencies] in
                await dependencies.preparePersistence()
            }

        case .startMessageStream:
            guard messageTask.task == nil else { return }
            messageTask.task = Task { [dependencies] in
                dependencies.log("Message stream started")
                let messages = await dependencies.decodeMessages()
                for await message in messages {
                    dependencies.log("Message received \(describe(message))")
                    await dependencies.applyMessage(message)
                }
                dependencies.log("Message stream finished")
            }

        case .sendBootstrapRequests:
            Task { [dependencies] in
                dependencies.log("Send configs-file")
                await dependencies.sendText(TydomCommand.configsFile().request)
                dependencies.log("Send devices-meta")
                await dependencies.sendText(TydomCommand.devicesMeta().request)
                dependencies.log("Send devices-cmeta")
                await dependencies.sendText(TydomCommand.devicesCmeta().request)
                dependencies.log("Send devices-data")
                await dependencies.sendText(TydomCommand.devicesData().request)
                dependencies.log("Send refresh-all")
                await dependencies.sendText(TydomCommand.refreshAll().request)
            }

        case .sendRefreshAll:
            Task { [dependencies] in
                dependencies.log("Send refresh-all")
                await dependencies.sendText(TydomCommand.refreshAll().request)
            }

        case .setAppActive(let isActive):
            Task { [dependencies] in
                await dependencies.setAppActive(isActive)
            }

        case .disconnectAndClearStoredData:
            Task { [weak self] in
                await self?.executeDisconnectFlow()
            }
        }
    }

    private func disconnect() async {
        messageTask.cancel()
        await dependencies.disconnectConnection()
    }

    func sendDeviceCommand(uniqueId: String, key: String, value: JSONValue) async {
        guard let device = await dependencies.deviceByID(uniqueId) else { return }

        let commandValue = deviceCommandValue(from: value)
        let command = TydomCommand.putDevicesData(
            deviceId: String(device.deviceId),
            endpointId: String(device.endpointId),
            name: key,
            value: commandValue
        )

        await dependencies.sendText(command.request)
    }

    private func executeDisconnectFlow() async {
        await disconnect()
        await dependencies.clearShutterState()
        await dependencies.clearStoredData()
        send(.disconnected)
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
