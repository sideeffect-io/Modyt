import Foundation
import SwiftUI
import Testing
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
        let (nextState, effects) = MainReducer.reduce(
            state: initialState,
            event: transition.event
        )

        #expect(nextState.featureState == transition.expected)
        #expect(effects == transition.expectedEffects)
    }

    @Test
    func reducerLeavesUnknownTransitionUntouched() {
        let initialState = MainState(featureState: .featureIsIdle)
        let (nextState, effects) = MainReducer.reduce(
            state: initialState,
            event: .appActiveWasReceived
        )

        #expect(nextState == initialState)
        #expect(effects.isEmpty)
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
            expected: .gatewayHandlingIsStarting,
            expectedEffects: [.handleGatewayMessages]
        )
    ]
}

@MainActor
struct MainStoreEffectTests {
    @Test
    func gatewayHandlingSuccessTransitionsToFeatureStarted() async {
        let store = makeStore(
            handleGatewayMessages: { .gatewayHandlingWasSuccessful }
        )

        store.send(.startingGatewayHandlingWasRequested)
        await settle()

        #expect(store.state.featureState == .featureIsStarted)
    }

    @Test
    func gatewayHandlingFailureTransitionsToGatewayHandlingInError() async {
        let store = makeStore(
            handleGatewayMessages: { .gatewayHandlingWasAFailure }
        )

        store.send(.startingGatewayHandlingWasRequested)
        await settle()

        #expect(store.state.featureState == .gatewayHandlingIsInError)
    }

    @Test
    func appActiveCheckCanDriveReconnectionFlow() async {
        let store = makeStore(
            handleGatewayMessages: { .gatewayHandlingWasSuccessful },
            checkGatewayConnection: { .reconnectionWasRequested },
            reconnectToGateway: { .reconnectionWasAFailure }
        )

        store.send(.startingGatewayHandlingWasRequested)
        await settle()
        #expect(store.state.featureState == .featureIsStarted)

        store.send(.appActiveWasReceived)
        await settle(cycles: 20)

        #expect(store.state.featureState == .reconnectionIsInError)
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
        await settle()
        store.send(.appActiveWasReceived)
        await settle()

        #expect(store.state.featureState == .featureIsStarted)
        #expect(await invocations.value() == 1)
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
        await settle()
        store.send(.appInactiveWasReceived)
        await settle()

        #expect(store.state.featureState == .featureIsStarted)
        #expect(await inactiveCalls.value() == 1)
    }

    @Test
    func reconnectionSuccessAndRefreshSuccessReturnToFeatureStartedAndSetAppActive() async {
        let setActiveCalls = Counter()
        let store = makeStore(
            handleGatewayMessages: { .gatewayHandlingWasSuccessful },
            setAppActive: {
                await setActiveCalls.increment()
            },
            checkGatewayConnection: { .reconnectionWasRequested },
            reconnectToGateway: { .reconnectionWasSuccessful }
        )

        store.send(.startingGatewayHandlingWasRequested)
        await settle()
        store.send(.appActiveWasReceived)
        await settle(cycles: 24)

        #expect(store.state.featureState == .featureIsStarted)
        #expect(await setActiveCalls.value() >= 1)
    }

    @Test
    func reconnectionSuccessAndRefreshFailureEndsInRefreshingDataError() async {
        let gatewayMessagesCounter = Counter()
        let store = makeStore(
            handleGatewayMessages: {
                let count = await gatewayMessagesCounter.incrementAndGet()
                return count == 1 ? .gatewayHandlingWasSuccessful : .gatewayHandlingWasAFailure
            },
            checkGatewayConnection: { .reconnectionWasRequested },
            reconnectToGateway: { .reconnectionWasSuccessful }
        )

        store.send(.startingGatewayHandlingWasRequested)
        await settle()
        store.send(.appActiveWasReceived)
        await settle(cycles: 24)

        #expect(store.state.featureState == .gatewayHandlingIsInError)
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
            dependencies: .init(
                handleGatewayMessages: handleGatewayMessages,
                disconnect: disconnect,
                setAppInactive: setAppInactive,
                setAppActive: setAppActive,
                checkGatewayConnection: checkGatewayConnection,
                reconnectToGateway: reconnectToGateway
            )
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
