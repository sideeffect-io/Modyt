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

struct AppState: Sendable, Equatable {
    var phase: Phase
    var devices: [DeviceRecord]
    var groupedDevices: [DeviceGroupSection]
    var favorites: [DeviceRecord]
    var isAppActive: Bool
    var shutterTargets: [String: ShutterStep]
    var shutterActualSteps: [String: ShutterStep]
    var shutterTargetOrigins: [String: ShutterStep]
    var shutterTargetIgnoredEcho: [String: Bool]

    static let initial = AppState(
        phase: .bootstrapping,
        devices: [],
        groupedDevices: [],
        favorites: [],
        isAppActive: true,
        shutterTargets: [:],
        shutterActualSteps: [:],
        shutterTargetOrigins: [:],
        shutterTargetIgnoredEcho: [:]
    )

    enum Phase: Sendable, Equatable {
        case bootstrapping
        case login(LoginState)
        case connecting
        case connected
        case error(String)
    }
}

struct DeviceGroupSection: Sendable, Equatable, Identifiable {
    let group: DeviceGroup
    let devices: [DeviceRecord]

    var id: DeviceGroup { group }
}

struct LoginState: Sendable, Equatable {
    var email: String = ""
    var password: String = ""
    var sites: [DeltaDoreClient.Site] = []
    var selectedSiteIndex: Int? = nil
    var isLoadingSites: Bool = false
    var isConnecting: Bool = false
    var errorMessage: String? = nil

    var canLoadSites: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.isEmpty
    }

    var canConnect: Bool {
        selectedSiteIndex != nil && !isConnecting
    }
}

extension AppState {
    func shutterTargetStep(for device: DeviceRecord) -> ShutterStep? {
        shutterTargets[device.uniqueId]
    }

    func shutterActualStep(for device: DeviceRecord) -> ShutterStep? {
        shutterActualSteps[device.uniqueId]
    }
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

private func reduceShutterDisplayState(
    devices: [DeviceRecord],
    currentActual: [String: ShutterStep],
    targets: [String: ShutterStep],
    origins: [String: ShutterStep],
    ignoredEcho: [String: Bool]
) -> (
    actual: [String: ShutterStep],
    targets: [String: ShutterStep],
    origins: [String: ShutterStep],
    ignoredEcho: [String: Bool]
) {
    var nextActualSteps: [String: ShutterStep] = [:]
    var nextTargets = targets
    var nextOrigins = origins
    var nextIgnoredEcho = ignoredEcho

    for device in devices where device.group == .shutter {
        guard let descriptor = device.primaryControlDescriptor(),
              descriptor.kind == .slider else { continue }
        let newStep = ShutterStep.nearestStep(for: descriptor.value, in: descriptor.range)
        let uniqueId = device.uniqueId
        let previousDisplayed = currentActual[uniqueId] ?? newStep
        if let target = targets[uniqueId] {
            let origin = origins[uniqueId] ?? previousDisplayed
            let hasIgnoredEcho = ignoredEcho[uniqueId] ?? false

            if newStep == target && !hasIgnoredEcho && previousDisplayed == origin {
                nextActualSteps[uniqueId] = previousDisplayed
                nextIgnoredEcho[uniqueId] = true
            } else {
                nextActualSteps[uniqueId] = newStep
                if newStep == target {
                    nextTargets.removeValue(forKey: uniqueId)
                    nextOrigins.removeValue(forKey: uniqueId)
                    nextIgnoredEcho.removeValue(forKey: uniqueId)
                }
            }
        } else {
            nextActualSteps[uniqueId] = newStep
            nextOrigins.removeValue(forKey: uniqueId)
            nextIgnoredEcho.removeValue(forKey: uniqueId)
        }
    }

    return (
        actual: nextActualSteps,
        targets: nextTargets,
        origins: nextOrigins,
        ignoredEcho: nextIgnoredEcho
    )
}

enum AppAction: Sendable {
    case onAppear
    case flowInspected(DeltaDoreClient.ConnectionFlowStatus)
    case loginEmailChanged(String)
    case loginPasswordChanged(String)
    case loadSitesTapped
    case sitesLoaded(Result<[DeltaDoreClient.Site], Error>)
    case siteSelected(Int)
    case connectTapped
    case connectionSucceeded
    case connectionFailed(String)
    case devicesUpdated([DeviceRecord])
    case setAppActive(Bool)
    case refreshRequested
    case toggleFavorite(String)
    case reorderFavorite(String, String)
    case deviceControlChanged(uniqueId: String, key: String, value: JSONValue)
    case disconnectTapped
    case disconnected
}

enum AppEffect: Sendable {
    case preparePersistence
    case startObservingDevices
    case inspectFlow
    case connectStored
    case listSites(email: String, password: String)
    case connectNew(email: String, password: String, siteIndex: Int?)
    case sendBootstrapRequests
    case sendRefreshAll
    case startMessageStream
    case setAppActive(Bool)
    case applyOptimisticUpdate(uniqueId: String, key: String, value: JSONValue)
    case sendDeviceCommand(uniqueId: String, key: String, value: JSONValue)
    case toggleFavorite(String)
    case reorderFavorite(from: String, to: String)
    case disconnect
}

enum AppReducer {
    static func reduce(state: AppState, action: AppAction) -> (AppState, [AppEffect]) {
        var state = state
        var effects: [AppEffect] = []

        switch action {
        case .onAppear:
            state.phase = .bootstrapping
            effects = [.preparePersistence, .startObservingDevices, .inspectFlow]

        case .flowInspected(let flow):
            switch flow {
            case .connectWithStoredCredentials:
                state.phase = .connecting
                effects = [.connectStored]
            case .connectWithNewCredentials:
                state.phase = .login(LoginState())
            }

        case .loginEmailChanged(let email):
            if case .login(var login) = state.phase {
                login.email = email
                login.errorMessage = nil
                state.phase = .login(login)
            }

        case .loginPasswordChanged(let password):
            if case .login(var login) = state.phase {
                login.password = password
                login.errorMessage = nil
                state.phase = .login(login)
            }

        case .loadSitesTapped:
            if case .login(var login) = state.phase, login.canLoadSites {
                login.isLoadingSites = true
                login.errorMessage = nil
                state.phase = .login(login)
                effects = [.listSites(email: login.email, password: login.password)]
            }

        case .sitesLoaded(let result):
            if case .login(var login) = state.phase {
                login.isLoadingSites = false
                switch result {
                case .success(let sites):
                    login.sites = sites
                    login.selectedSiteIndex = sites.count == 1 ? 0 : nil
                    login.errorMessage = nil
                case .failure(let error):
                    login.errorMessage = error.localizedDescription
                }
                state.phase = .login(login)
            }

        case .siteSelected(let index):
            if case .login(var login) = state.phase {
                login.selectedSiteIndex = index
                login.errorMessage = nil
                state.phase = .login(login)
            }

        case .connectTapped:
            if case .login(var login) = state.phase, login.canConnect {
                login.isConnecting = true
                login.errorMessage = nil
                state.phase = .login(login)
                effects = [.connectNew(email: login.email, password: login.password, siteIndex: login.selectedSiteIndex)]
            }

        case .connectionSucceeded:
            state.phase = .connected
            effects = [.startMessageStream, .sendBootstrapRequests, .setAppActive(state.isAppActive)]

        case .connectionFailed(let message):
            switch state.phase {
            case .login(var login):
                login.isConnecting = false
                login.errorMessage = message
                state.phase = .login(login)
            default:
                state.phase = .error(message)
            }

        case .devicesUpdated(let devices):
            state.devices = devices
            let derived = deriveDeviceCollections(from: devices)
            state.groupedDevices = derived.grouped
            state.favorites = derived.favorites
            let shutterState = reduceShutterDisplayState(
                devices: devices,
                currentActual: state.shutterActualSteps,
                targets: state.shutterTargets,
                origins: state.shutterTargetOrigins,
                ignoredEcho: state.shutterTargetIgnoredEcho
            )
            state.shutterActualSteps = shutterState.actual
            state.shutterTargets = shutterState.targets
            state.shutterTargetOrigins = shutterState.origins
            state.shutterTargetIgnoredEcho = shutterState.ignoredEcho

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
            let shutterDescriptor = state.devices.first(where: { $0.uniqueId == uniqueId })
                .flatMap { device -> DeviceControlDescriptor? in
                    guard device.group == .shutter else { return nil }
                    guard let descriptor = device.primaryControlDescriptor(), descriptor.kind == .slider else { return nil }
                    return descriptor.key == key ? descriptor : nil
                }

            if let shutterDescriptor,
               let numberValue = value.numberValue {
                let step = ShutterStep.nearestStep(for: numberValue, in: shutterDescriptor.range)
                state.shutterTargets[uniqueId] = step
                let origin = state.shutterActualSteps[uniqueId]
                    ?? ShutterStep.nearestStep(for: shutterDescriptor.value, in: shutterDescriptor.range)
                state.shutterTargetOrigins[uniqueId] = origin
                state.shutterTargetIgnoredEcho[uniqueId] = false
            }

            if shutterDescriptor != nil {
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
            state.shutterTargets = [:]
            state.shutterActualSteps = [:]
            state.shutterTargetOrigins = [:]
            state.shutterTargetIgnoredEcho = [:]
            state.phase = .bootstrapping
            effects = [.disconnect]

        case .disconnected:
            state.phase = .bootstrapping
            effects = [.inspectFlow]
        }

        return (state, effects)
    }
}

@Observable
@MainActor
final class AppStore {
    private(set) var state: AppState

    private let environment: AppEnvironment
    private var connection: TydomConnection?
    private var messageTask: Task<Void, Never>?
    private var deviceObserverTask: Task<Void, Never>?

    init(environment: AppEnvironment) {
        self.environment = environment
        self.state = .initial
    }

    func send(_ action: AppAction) {
        let (next, effects) = AppReducer.reduce(state: state, action: action)
        state = next
        handle(effects)
    }

    private func handle(_ effects: [AppEffect]) {
        for effect in effects {
            handle(effect)
        }
    }

    private func handle(_ effect: AppEffect) {
        switch effect {
        case .preparePersistence:
            Task { [environment] in
                try? await environment.repository.startIfNeeded()
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

        case .inspectFlow:
            Task { [environment] in
                let flow = await environment.client.inspectConnectionFlow()
                await MainActor.run {
                    self.send(.flowInspected(flow))
                }
            }

        case .connectStored:
            Task { [environment] in
                do {
                    let session = try await environment.client.connectWithStoredCredentials(options: .init())
                    await MainActor.run {
                        self.connection = session.connection
                        self.send(.connectionSucceeded)
                    }
                } catch {
                    await MainActor.run {
                        self.send(.connectionFailed(error.localizedDescription))
                    }
                }
            }

        case .listSites(let email, let password):
            Task { [environment] in
                do {
                    let credentials = TydomConnection.CloudCredentials(email: email, password: password)
                    let sites = try await environment.client.listSites(cloudCredentials: credentials)
                    await MainActor.run {
                        self.send(.sitesLoaded(.success(sites)))
                    }
                } catch {
                    await MainActor.run {
                        self.send(.sitesLoaded(.failure(error)))
                    }
                }
            }

        case .connectNew(let email, let password, let siteIndex):
            Task { [environment] in
                do {
                    let credentials = TydomConnection.CloudCredentials(email: email, password: password)
                    let session = try await environment.client.connectWithNewCredentials(
                        options: .init(mode: .auto(cloudCredentials: credentials)),
                        selectSiteIndex: { _ in siteIndex }
                    )
                    await MainActor.run {
                        self.connection = session.connection
                        self.send(.connectionSucceeded)
                    }
                } catch {
                    await MainActor.run {
                        self.send(.connectionFailed(error.localizedDescription))
                    }
                }
            }

        case .sendRefreshAll:
            Task { [weak self] in
                guard let connection = self?.connection else { return }
                self?.environment.log("Send refresh-all")
                try? await connection.send(text: TydomCommand.refreshAll().request)
            }

        case .sendBootstrapRequests:
            Task { [weak self] in
                guard let connection = self?.connection else { return }
                self?.environment.log("Send configs-file")
                try? await connection.send(text: TydomCommand.configsFile().request)
                self?.environment.log("Send devices-meta")
                try? await connection.send(text: TydomCommand.devicesMeta().request)
                self?.environment.log("Send devices-cmeta")
                try? await connection.send(text: TydomCommand.devicesCmeta().request)
                self?.environment.log("Send devices-data")
                try? await connection.send(text: TydomCommand.devicesData().request)
                self?.environment.log("Send refresh-all")
                try? await connection.send(text: TydomCommand.refreshAll().request)
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

        case .setAppActive(let isActive):
            Task { [weak self] in
                guard let connection = self?.connection else { return }
                await connection.setAppActive(isActive)
            }

        case .applyOptimisticUpdate(let uniqueId, let key, let value):
            Task { [environment] in
                await environment.repository.applyOptimisticUpdate(uniqueId: uniqueId, key: key, value: value)
            }

        case .sendDeviceCommand(let uniqueId, let key, let value):
            Task { [weak self] in
                guard let self, let connection = self.connection else { return }
                guard let device = self.state.devices.first(where: { $0.uniqueId == uniqueId }) else { return }
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

        case .disconnect:
            Task { [weak self, environment] in
                guard let self else { return }
                await self.disconnect()
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
