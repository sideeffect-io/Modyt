import Foundation
import SwiftUI
import Testing
@testable import DeltaDoreClient
@testable import MoDyt

struct MainReducerTransitionTests {
    struct TransitionCase: Sendable {
        let initial: MainFeatureState
        let event: MainEvent
        let expected: MainFeatureState
        let expectedEffects: [MainEffect]
    }

    @Test(arguments: transitionCases)
    func reducerAppliesConfiguredTransition(_ transition: TransitionCase) {
        let initialState = MainState(featureState: transition.initial)
        let transitionResult = MainStore.StateMachine.reduce(
            initialState,
            transition.event
        )

        #expect(transitionResult.state.featureState == transition.expected)
        #expect(transitionResult.effects == transition.expectedEffects)
    }

    @Test
    func reducerLeavesUnknownTransitionUntouched() {
        let initialState = MainState(featureState: .featureIsIdle)
        let transition = MainStore.StateMachine.reduce(
            initialState,
            .appActiveWasReceived
        )

        #expect(transition.state == initialState)
        #expect(transition.effects.isEmpty)
    }

    private static let transitionCases: [TransitionCase] = [
        .init(
            initial: .featureIsIdle,
            event: .startingGatewayHandlingWasRequested,
            expected: .gatewayHandlingIsStarting,
            expectedEffects: [.handleGatewayMessages]
        ),
        .init(
            initial: .gatewayHandlingIsStarting,
            event: .gatewayHandlingWasAFailure,
            expected: .gatewayHandlingIsInError,
            expectedEffects: []
        ),
        .init(
            initial: .gatewayHandlingIsInError,
            event: .startingGatewayHandlingWasRequested,
            expected: .gatewayHandlingIsStarting,
            expectedEffects: [.handleGatewayMessages]
        ),
        .init(
            initial: .gatewayHandlingIsInError,
            event: .disconnectionWasRequested,
            expected: .disconnectionIsInProgress,
            expectedEffects: [.disconnect]
        ),
        .init(
            initial: .disconnectionIsInProgress,
            event: .disconnectionWasSuccessful,
            expected: .userIsDisconnected,
            expectedEffects: []
        ),
        .init(
            initial: .gatewayHandlingIsStarting,
            event: .gatewayHandlingWasSuccessful,
            expected: .featureIsStarted,
            expectedEffects: [.setAppActive]
        ),
        .init(
            initial: .featureIsStarted,
            event: .appInactiveWasReceived,
            expected: .featureIsStarted,
            expectedEffects: [.setAppInactive]
        ),
        .init(
            initial: .featureIsStarted,
            event: .appActiveWasReceived,
            expected: .featureIsStarted,
            expectedEffects: [.checkGatewayConnection]
        ),
        .init(
            initial: .featureIsStarted,
            event: .reconnectionWasRequested,
            expected: .reconnectionIsInProgress,
            expectedEffects: [.reconnectToGateway]
        ),
        .init(
            initial: .reconnectionIsInProgress,
            event: .reconnectionWasAFailure,
            expected: .reconnectionIsInError,
            expectedEffects: []
        ),
        .init(
            initial: .reconnectionIsInError,
            event: .reconnectionWasRequested,
            expected: .reconnectionIsInProgress,
            expectedEffects: [.reconnectToGateway]
        ),
        .init(
            initial: .reconnectionIsInError,
            event: .disconnectionWasRequested,
            expected: .disconnectionIsInProgress,
            expectedEffects: [.disconnect]
        ),
        .init(
            initial: .reconnectionIsInProgress,
            event: .reconnectionWasSuccessful,
            expected: .featureIsStarted,
            expectedEffects: []
        )
    ]
}

struct MainMessageStreamObservationStateTests {
    @Test
    func finishingOldTaskDoesNotClearNewActiveTask() {
        var state = MainMessageStreamObservationState()

        let initialRegistration = state.register(taskID: 1)
        state.cancel()
        let replacementRegistration = state.register(taskID: 2)
        let oldTaskDidFinish = state.finish(taskID: 1)

        #expect(initialRegistration)
        #expect(replacementRegistration)
        #expect(oldTaskDidFinish == false)
        #expect(state.activeTaskID == 2)
    }

    @Test
    func finishingCurrentTaskClearsActiveTask() {
        var state = MainMessageStreamObservationState()

        let registration = state.register(taskID: 7)
        let finishedCurrentTask = state.finish(taskID: 7)

        #expect(registration)
        #expect(finishedCurrentTask)
        #expect(state.activeTaskID == nil)
    }
}

@MainActor
struct MainStoreEffectTests {
    @Test
    func gatewayHandlingSuccessTransitionsToFeatureStarted() async {
        let store = makeStore(
            handleGatewayMessages: { .gatewayHandlingWasSuccessful }
        )

        store.send(.startingGatewayHandlingWasRequested)
        #expect(
            await waitUntil {
                store.state.featureState == .featureIsStarted
            }
        )
    }

    @Test
    func gatewayHandlingFailureTransitionsToGatewayHandlingInError() async {
        let store = makeStore(
            handleGatewayMessages: { .gatewayHandlingWasAFailure }
        )

        store.send(.startingGatewayHandlingWasRequested)
        #expect(
            await waitUntil {
                store.state.featureState == .gatewayHandlingIsInError
            }
        )
    }

    @Test
    func appActiveCheckCanDriveReconnectionFlow() async {
        let store = makeStore(
            handleGatewayMessages: { .gatewayHandlingWasSuccessful },
            checkGatewayConnection: { .reconnectionWasRequested },
            reconnectToGateway: { .reconnectionWasAFailure }
        )

        store.send(.startingGatewayHandlingWasRequested)
        #expect(
            await waitUntil {
                store.state.featureState == .featureIsStarted
            }
        )

        store.send(.appActiveWasReceived)
        #expect(
            await waitUntil(cycles: 60) {
                store.state.featureState == .reconnectionIsInError
            }
        )
    }

    @Test
    func checkGatewayConnectionCanCompleteWithoutStateChange() async {
        let invocations = Counter()
        let store = makeStore(
            handleGatewayMessages: { .gatewayHandlingWasSuccessful },
            checkGatewayConnection: {
                await invocations.increment()
                return nil
            }
        )

        store.send(.startingGatewayHandlingWasRequested)
        #expect(
            await waitUntil {
                store.state.featureState == .featureIsStarted
            }
        )
        store.send(.appActiveWasReceived)

        #expect(store.state.featureState == .featureIsStarted)
        #expect(await waitUntilAsync(cycles: 40) {
            await invocations.value() == 1
        })
    }

    @Test
    func appInactiveTriggersSetAppInactiveEffect() async {
        let inactiveCalls = Counter()
        let store = makeStore(
            handleGatewayMessages: { .gatewayHandlingWasSuccessful },
            setAppInactive: {
                await inactiveCalls.increment()
            }
        )

        store.send(.startingGatewayHandlingWasRequested)
        #expect(
            await waitUntil {
                store.state.featureState == .featureIsStarted
            }
        )
        store.send(.appInactiveWasReceived)

        #expect(store.state.featureState == .featureIsStarted)
        #expect(await waitUntilAsync {
            await inactiveCalls.value() == 1
        })
    }

    @Test
    func reconnectionSuccessReturnsDirectlyToFeatureStarted() async {
        let gatewayMessagesCounter = Counter()
        let store = makeStore(
            handleGatewayMessages: {
                await gatewayMessagesCounter.increment()
                return .gatewayHandlingWasSuccessful
            },
            checkGatewayConnection: { .reconnectionWasRequested },
            reconnectToGateway: { .reconnectionWasSuccessful }
        )

        store.send(.startingGatewayHandlingWasRequested)
        #expect(
            await waitUntil {
                store.state.featureState == .featureIsStarted
            }
        )
        store.send(.appActiveWasReceived)

        #expect(
            await waitUntil {
                store.state.featureState == .featureIsStarted
            }
        )
        #expect(await gatewayMessagesCounter.value() == 1)
    }

    @Test
    func reconnectionRefreshFailureEndsInReconnectionError() async {
        let store = makeStore(
            handleGatewayMessages: { .gatewayHandlingWasSuccessful },
            checkGatewayConnection: { .reconnectionWasRequested },
            reconnectToGateway: { .reconnectionWasAFailure }
        )

        store.send(.startingGatewayHandlingWasRequested)
        #expect(
            await waitUntil {
                store.state.featureState == .featureIsStarted
            }
        )
        store.send(.appActiveWasReceived)
        #expect(
            await waitUntil(cycles: 80) {
                store.state.featureState == .reconnectionIsInError
            }
        )
    }

    @Test
    func retryCancelsStaleGatewayTaskResult() async {
        let invocations = Counter()
        let store = makeStore(
            handleGatewayMessages: {
                let invocation = await invocations.incrementAndGet()
                if invocation == 1 {
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    return .gatewayHandlingWasSuccessful
                }
                return .gatewayHandlingWasAFailure
            }
        )

        store.send(.startingGatewayHandlingWasRequested)
        await settle()
        store.send(.gatewayHandlingWasAFailure)
        store.send(.startingGatewayHandlingWasRequested)
        await settle(cycles: 30)
        try? await Task.sleep(nanoseconds: 350_000_000)
        await settle(cycles: 30)

        #expect(store.state.featureState == .gatewayHandlingIsInError)
        #expect(await invocations.value() == 2)
    }

    @Test
    func disconnectCancelsOtherInFlightEffectsAndEndsDisconnected() async {
        let disconnectCalls = Counter()
        let store = makeStore(
            handleGatewayMessages: {
                try? await Task.sleep(nanoseconds: 350_000_000)
                return .gatewayHandlingWasSuccessful
            },
            disconnect: {
                await disconnectCalls.increment()
            }
        )

        store.send(.startingGatewayHandlingWasRequested)
        await settle()
        store.send(.gatewayHandlingWasAFailure)
        store.send(.disconnectionWasRequested)
        await settle(cycles: 30)
        try? await Task.sleep(nanoseconds: 450_000_000)
        await settle(cycles: 30)

        #expect(store.state.featureState == .userIsDisconnected)
        #expect(await disconnectCalls.value() == 1)
    }

    private func makeStore(
        handleGatewayMessages: @escaping @Sendable () async -> MainEvent = { .gatewayHandlingWasSuccessful },
        disconnect: @escaping @Sendable () async -> Void = {},
        setAppInactive: @escaping @Sendable () async -> Void = {},
        setAppActive: @escaping @Sendable () async -> Void = {},
        checkGatewayConnection: @escaping @Sendable () async -> MainEvent? = { nil },
        reconnectToGateway: @escaping @Sendable () async -> MainEvent = { .reconnectionWasSuccessful }
    ) -> MainStore {
        MainStore(
            handleGatewayMessages: .init(handleGatewayMessages: handleGatewayMessages),
            disconnect: .init(disconnect: disconnect),
            setAppInactive: .init(setAppInactive: setAppInactive),
            setAppActive: .init(setAppActive: setAppActive),
            checkGatewayConnection: .init(checkGatewayConnection: checkGatewayConnection),
            reconnectToGateway: .init(reconnectToGateway: reconnectToGateway)
        )
    }
}

struct MainGatewayDataRequestPipelineTests {
    @Test
    func pipelineSendsExpectedRequestsInOrder() async throws {
        let txGenerator = TransactionIDSequence(values: [
            "tx-1",
            "tx-2",
            "tx-3",
            "tx-4",
            "tx-5",
            "tx-6"
        ])
        let sentRequests = Recorder<String>()
        let generatedTransactionIDs = Recorder<String>()

        let pipeline = MainGatewayDataRequestPipeline(
            requests: MainGatewayDataRequestPipeline.defaultRequests,
            makeTransactionID: {
                let transactionId = await txGenerator.next()
                await generatedTransactionIDs.append(transactionId)
                return transactionId
            },
            sendText: { request in
                await sentRequests.append(request)
            }
        )

        try await pipeline.run()

        let requestPaths = await sentRequests.values().map(extractPath(from:))
        #expect(requestPaths == [
            "/configs/file",
            "/devices/meta",
            "/devices/cmeta",
            "/devices/data",
            "/scenarios/file",
            "/groups/file"
        ])

        let generated = await generatedTransactionIDs.values()
        #expect(generated == ["tx-1", "tx-2", "tx-3", "tx-4", "tx-5", "tx-6"])
        #expect(Set(generated).count == 6)
    }

    private func extractPath(from request: String) -> String {
        let firstLine = request.split(whereSeparator: \.isNewline).first ?? ""
        let components = firstLine.split(separator: " ")
        guard components.count >= 2 else { return "" }
        return String(components[1]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct MainRuntimeTests {
    @Test
    func foregroundLocalHealthCheckUsesSingleShortProbe() async throws {
        let databasePath = testTemporarySQLitePath("MainRuntimeTests-local-probe")
        defer { try? FileManager.default.removeItem(atPath: databasePath) }

        let localConnection = makeMainRuntimeConnection(mode: .local(host: "192.168.1.10"))
        let probeTimeouts = Recorder<TimeInterval>()
        let gatewayClient = makeMainRuntimeGatewayClient(
            connectStored: { _ in
                DeltaDoreClient.ConnectionSession(connection: localConnection)
            },
            probeConnectionOnce: { _, timeout in
                await probeTimeouts.append(timeout)
                return true
            }
        )
        _ = try await gatewayClient.connectWithStoredCredentials(options: .init(mode: .auto))

        let runtime = MainRuntime(
            gatewayClient: gatewayClient,
            router: makeMainRuntimeRouter(databasePath: databasePath),
            requestGatewayData: {}
        )

        let event = await runtime.checkGatewayConnection()

        #expect(event == nil)
        #expect(await probeTimeouts.values() == [0.35])
    }

    @Test
    func foregroundRemoteConnectionRequestsReconnectWithoutProbing() async throws {
        let databasePath = testTemporarySQLitePath("MainRuntimeTests-remote-reconnect")
        defer { try? FileManager.default.removeItem(atPath: databasePath) }

        let remoteConnection = makeMainRuntimeConnection(mode: .remote(host: "mediation.tydom.com"))
        let probeCalls = Counter()
        let gatewayClient = makeMainRuntimeGatewayClient(
            connectStored: { _ in
                DeltaDoreClient.ConnectionSession(connection: remoteConnection)
            },
            probeConnectionOnce: { _, _ in
                await probeCalls.increment()
                return true
            }
        )
        _ = try await gatewayClient.connectWithStoredCredentials(options: .init(mode: .forceRemote))

        let runtime = MainRuntime(
            gatewayClient: gatewayClient,
            router: makeMainRuntimeRouter(databasePath: databasePath),
            requestGatewayData: {}
        )

        let event = await runtime.checkGatewayConnection()

        #expect(event == .reconnectionWasRequested)
        #expect(await probeCalls.value() == 0)
    }

    @Test
    func reconnectToGatewayUsesStoredRenewalWithoutSecondProbe() async throws {
        let databasePath = testTemporarySQLitePath("MainRuntimeTests-reconnect")
        defer { try? FileManager.default.removeItem(atPath: databasePath) }

        let currentRemoteConnection = makeMainRuntimeConnection(mode: .remote(host: "current.tydom.com"))
        let recoveredLocalConnection = makeMainRuntimeConnection(mode: .local(host: "192.168.1.10"))
        let modes = Recorder<String>()
        let probeCalls = Counter()
        let requestCalls = Counter()
        let gatewayClient = makeMainRuntimeGatewayClient(
            connectStored: { options in
                switch options.mode {
                case .forceRemote:
                    await modes.append("forceRemote")
                    return DeltaDoreClient.ConnectionSession(connection: currentRemoteConnection)
                case .auto:
                    await modes.append("auto")
                    return DeltaDoreClient.ConnectionSession(connection: recoveredLocalConnection)
                case .forceLocal:
                    throw MainRuntimeTestFailure.unexpectedLocalReconnect
                }
            },
            probeConnection: { _, _ in
                await probeCalls.increment()
                return false
            },
            probeConnectionOnce: { _, _ in
                await probeCalls.increment()
                return false
            }
        )
        _ = try await gatewayClient.connectWithStoredCredentials(options: .init(mode: .forceRemote))

        let runtime = MainRuntime(
            gatewayClient: gatewayClient,
            router: makeMainRuntimeRouter(databasePath: databasePath),
            requestGatewayData: {
                await requestCalls.increment()
            }
        )

        let event = await runtime.reconnectToGateway()

        #expect(event == .reconnectionWasSuccessful)
        #expect(await modes.values() == ["forceRemote", "auto"])
        #expect(await probeCalls.value() == 0)
        #expect(await requestCalls.value() == 1)
        #expect(await gatewayClient.currentConnectionMode() == .local(host: "192.168.1.10"))
    }
}

struct MainViewPresentationStateTests {
    struct MappingCase: Sendable {
        let state: MainFeatureState
        let expectedPresentation: MainPresentationState
        let shouldBlock: Bool
    }

    @Test(arguments: mappingCases)
    func mappingMatchesFeatureState(_ testCase: MappingCase) {
        #expect(mainPresentationState(for: testCase.state) == testCase.expectedPresentation)
        #expect(shouldBlockMainInteraction(for: testCase.state) == testCase.shouldBlock)
    }

    private static let mappingCases: [MappingCase] = [
        .init(state: .featureIsIdle, expectedPresentation: .none, shouldBlock: false),
        .init(state: .gatewayHandlingIsStarting, expectedPresentation: .progress("Loading gateway data"), shouldBlock: true),
        .init(state: .gatewayHandlingIsInError, expectedPresentation: .gatewayHandlingError, shouldBlock: true),
        .init(state: .disconnectionIsInProgress, expectedPresentation: .progress("Disconnecting"), shouldBlock: true),
        .init(state: .userIsDisconnected, expectedPresentation: .none, shouldBlock: false),
        .init(state: .featureIsStarted, expectedPresentation: .none, shouldBlock: false),
        .init(state: .reconnectionIsInProgress, expectedPresentation: .progress("Reconnecting"), shouldBlock: true),
        .init(state: .reconnectionIsInError, expectedPresentation: .reconnectionError, shouldBlock: true)
    ]
}

struct MainViewBehaviorContractTests {
    struct ScenePhaseCase: Sendable {
        let phase: ScenePhase
        let expectedEvent: MainEvent
    }

    struct ParentNotificationCase: Sendable {
        let previous: MainFeatureState
        let current: MainFeatureState
        let expected: Bool
    }

    @Test(arguments: scenePhaseCases)
    func scenePhaseIsMappedToExpectedEvent(_ testCase: ScenePhaseCase) {
        #expect(mainEvent(for: testCase.phase) == testCase.expectedEvent)
    }

    @MainActor
    @Test
    func settingsDisconnectCallbackForwardsToParent() {
        let recorder = MainActorRecorder()
        let callback: () -> Void = {
            recorder.record()
        }

        callback()

        #expect(recorder.count == 1)
    }

    @Test(arguments: parentNotificationCases)
    func userDisconnectionChangeNotifiesParent(_ testCase: ParentNotificationCase) {
        #expect(
            shouldNotifyParentOnMainFeatureStateChange(
                previous: testCase.previous,
                current: testCase.current
            ) == testCase.expected
        )
    }

    private static let scenePhaseCases: [ScenePhaseCase] = [
        .init(phase: .active, expectedEvent: .appActiveWasReceived),
        .init(phase: .inactive, expectedEvent: .appInactiveWasReceived),
        .init(phase: .background, expectedEvent: .appInactiveWasReceived)
    ]

    private static let parentNotificationCases: [ParentNotificationCase] = [
        .init(previous: .featureIsStarted, current: .userIsDisconnected, expected: true),
        .init(previous: .userIsDisconnected, current: .userIsDisconnected, expected: false),
        .init(previous: .featureIsStarted, current: .featureIsStarted, expected: false),
        .init(previous: .gatewayHandlingIsInError, current: .disconnectionIsInProgress, expected: false)
    ]
}

@MainActor
private final class MainActorRecorder {
    private(set) var count: Int = 0

    func record() {
        count += 1
    }
}

private actor Counter {
    private var count: Int = 0

    func increment() {
        count += 1
    }

    func incrementAndGet() -> Int {
        count += 1
        return count
    }

    func value() -> Int {
        count
    }
}

private actor Recorder<Value: Sendable> {
    private var storage: [Value] = []

    func append(_ value: Value) {
        storage.append(value)
    }

    func values() -> [Value] {
        storage
    }
}

private actor TransactionIDSequence {
    private var values: [String]

    init(values: [String]) {
        self.values = values
    }

    func next() -> String {
        if values.isEmpty {
            return UUID().uuidString
        }
        return values.removeFirst()
    }
}

private func settle(cycles: Int = 12) async {
    for _ in 0..<cycles {
        await Task.yield()
    }
}

@MainActor
private func waitUntil(
    cycles: Int = 40,
    condition: @escaping @MainActor () -> Bool
) async -> Bool {
    for _ in 0..<cycles {
        if condition() {
            return true
        }
        await Task.yield()
    }
    return condition()
}

private func waitUntilAsync(
    cycles: Int = 40,
    condition: @escaping @Sendable () async -> Bool
) async -> Bool {
    for _ in 0..<cycles {
        if await condition() {
            return true
        }
        await Task.yield()
    }
    return await condition()
}

private enum MainRuntimeTestFailure: Error {
    case unexpectedStoredConnect
    case unexpectedLocalReconnect
}

private func makeMainRuntimeGatewayClient(
    connectStored: @escaping @Sendable (DeltaDoreClient.StoredCredentialsFlowOptions) async throws -> DeltaDoreClient.ConnectionSession = { _ in
        throw MainRuntimeTestFailure.unexpectedStoredConnect
    },
    probeConnection: @escaping @Sendable (TydomConnection, TimeInterval) async -> Bool = { _, _ in false },
    probeConnectionOnce: @escaping @Sendable (TydomConnection, TimeInterval) async -> Bool = { _, _ in false }
) -> DeltaDoreClient {
    DeltaDoreClient(
        dependencies: .init(
            inspectFlow: { .connectWithStoredCredentials },
            connectStored: connectStored,
            connectNew: { _, _ in
                throw MainRuntimeTestFailure.unexpectedStoredConnect
            },
            listSites: { _ in [] },
            listSitesPayload: { _ in Data() },
            clearStoredData: {},
            probeConnection: probeConnection,
            probeConnectionOnce: probeConnectionOnce
        )
    )
}

private func makeMainRuntimeRouter(
    databasePath: String
) -> TydomMessageRepositoryRouter {
    TydomMessageRepositoryRouter(
        deviceRepository: DeviceRepository.makeDeviceRepository(databasePath: databasePath),
        groupRepository: GroupRepository.makeGroupRepository(databasePath: databasePath),
        sceneRepository: SceneRepository.makeSceneRepository(databasePath: databasePath),
        ackRepository: ACKRepository()
    )
}

private func makeMainRuntimeConnection(
    mode: TydomConnection.Configuration.Mode
) -> TydomConnection {
    TydomConnection(
        configuration: .init(
            mode: mode,
            mac: "AA:BB:CC:DD:EE:FF",
            password: "pass"
        )
    )
}
