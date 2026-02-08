import Testing
import DeltaDoreClient
@testable import MoDyt

@MainActor
struct RootTabStoreTests {
    @Test
    func disconnectedEventEmitsDelegateEvent() {
        let store = RootTabStore(dependencies: makeDependencies())
        var didEmit = false

        store.onDelegateEvent = { delegateEvent in
            if case .didDisconnect = delegateEvent {
                didEmit = true
            }
        }

        store.send(.disconnected)

        #expect(didEmit)
    }

    @Test
    func onStartTriggersBootstrapAndAppliesIncomingMessage() async {
        let messageStream = BufferedStreamBox<TydomMessage>()
        let sendRecorder = TestRecorder<String>()
        let applyRecorder = TestRecorder<TydomMessage>()
        let prepareCounter = Counter()
        let appActiveRecorder = TestRecorder<Bool>()

        let store = RootTabStore(
            dependencies: makeDependencies(
                preparePersistence: {
                    await prepareCounter.increment()
                },
                decodeMessages: {
                    messageStream.stream
                },
                applyMessage: { message in
                    await applyRecorder.record(message)
                },
                sendText: { request in
                    await sendRecorder.record(request)
                },
                setAppActive: { isActive in
                    await appActiveRecorder.record(isActive)
                }
            )
        )

        store.send(.onStart)
        messageStream.yield(.gatewayInfo(.init(payload: [:]), transactionId: "tx-1"))
        await settleAsyncState(iterations: 16)

        #expect(await prepareCounter.value == 1)
        #expect(await appActiveRecorder.values == [true])

        let requests = await sendRecorder.values
        #expect(requests.count == 5)
        #expect(requests.contains(where: { $0.contains("GET /configs/file HTTP/1.1") }))
        #expect(requests.contains(where: { $0.contains("GET /devices/meta HTTP/1.1") }))
        #expect(requests.contains(where: { $0.contains("GET /devices/cmeta HTTP/1.1") }))
        #expect(requests.contains(where: { $0.contains("GET /devices/data HTTP/1.1") }))
        #expect(requests.contains(where: { $0.contains("POST /refresh/all HTTP/1.1") }))

        let applied = await applyRecorder.values
        #expect(applied == [.gatewayInfo(.init(payload: [:]), transactionId: "tx-1")])
    }

    @Test
    func startMessageStreamRunsOnceWhenOnStartRepeated() async {
        let messageStream = BufferedStreamBox<TydomMessage>()
        let decodeCounter = Counter()
        let store = RootTabStore(
            dependencies: makeDependencies(
                decodeMessages: {
                    await decodeCounter.increment()
                    return messageStream.stream
                }
            )
        )

        store.send(.onStart)
        store.send(.onStart)
        await settleAsyncState(iterations: 16)

        #expect(await decodeCounter.value == 1)
    }

    @Test
    func refreshRequestedSendsRefreshAllCommand() async {
        let recorder = TestRecorder<String>()
        let store = RootTabStore(
            dependencies: makeDependencies(
                sendText: { text in
                    await recorder.record(text)
                }
            )
        )

        store.send(.refreshRequested)
        await settleAsyncState()

        let sent = await recorder.values
        #expect(sent.count == 1)
        #expect(sent[0].contains("POST /refresh/all HTTP/1.1"))
    }

    @Test
    func setAppActiveUpdatesStateAndForwardsFlag() async {
        let recorder = TestRecorder<Bool>()
        let store = RootTabStore(
            dependencies: makeDependencies(
                setAppActive: { isActive in
                    await recorder.record(isActive)
                }
            )
        )

        store.send(.setAppActive(false))
        store.send(.setAppActive(true))
        await settleAsyncState()

        #expect(store.state.isAppActive)
        #expect(await recorder.values == [false, true])
    }

    @Test
    func disconnectRequestedDisconnectsAndClearsBeforeDelegateEvent() async {
        let disconnectCounter = Counter()
        let clearShutterCounter = Counter()
        let clearStoredDataCounter = Counter()
        var didDisconnect = false

        let store = RootTabStore(
            dependencies: makeDependencies(
                disconnectConnection: {
                    await disconnectCounter.increment()
                },
                clearShutterState: {
                    await clearShutterCounter.increment()
                },
                clearStoredData: {
                    await clearStoredDataCounter.increment()
                }
            ),
            onDelegateEvent: { event in
                if case .didDisconnect = event {
                    didDisconnect = true
                }
            }
        )

        store.send(.disconnectRequested)
        await settleAsyncState(iterations: 16)

        #expect(await disconnectCounter.value == 1)
        #expect(await clearShutterCounter.value == 1)
        #expect(await clearStoredDataCounter.value == 1)
        #expect(didDisconnect)
    }

    @Test
    func sendDeviceCommandMapsValuesToLegacyCommandPayload() async {
        let recorder = TestRecorder<String>()
        let store = RootTabStore(
            dependencies: makeDependencies(
                sendText: { text in
                    await recorder.record(text)
                },
                deviceByID: { _ in
                    TestSupport.makeDevice(
                        uniqueId: "light-1",
                        name: "Desk",
                        usage: "light",
                        data: ["on": .bool(false)]
                    )
                }
            )
        )

        await store.sendDeviceCommand(uniqueId: "light-1", key: "on", value: .bool(true))
        await store.sendDeviceCommand(uniqueId: "light-1", key: "level", value: .number(49.6))
        await store.sendDeviceCommand(uniqueId: "light-1", key: "mode", value: .string("eco"))
        await store.sendDeviceCommand(uniqueId: "light-1", key: "custom", value: .object(["key": .string("value")]))

        let requests = await recorder.values
        #expect(requests.count == 4)
        #expect(requests.allSatisfy { $0.contains("PUT /devices/1/endpoints/1/data HTTP/1.1") })
        #expect(requests[0].contains("\"name\":\"on\",\"value\":true"))
        #expect(requests[1].contains("\"name\":\"level\",\"value\":\"50\""))
        #expect(requests[2].contains("\"name\":\"mode\",\"value\":\"eco\""))
        #expect(requests[3].contains("\"name\":\"custom\",\"value\":null"))
    }

    @Test
    func sendDeviceCommandDoesNothingWhenDeviceIsMissing() async {
        let recorder = TestRecorder<String>()
        let store = RootTabStore(
            dependencies: makeDependencies(
                sendText: { text in
                    await recorder.record(text)
                },
                deviceByID: { _ in nil }
            )
        )

        await store.sendDeviceCommand(uniqueId: "missing", key: "on", value: .bool(true))

        #expect((await recorder.values).isEmpty)
    }

    private func makeDependencies(
        log: @escaping (String) -> Void = { _ in },
        preparePersistence: @escaping () async -> Void = {},
        decodeMessages: @escaping () async -> AsyncStream<TydomMessage> = {
            AsyncStream { continuation in
                continuation.finish()
            }
        },
        applyMessage: @escaping (TydomMessage) async -> Void = { _ in },
        sendText: @escaping (String) async -> Void = { _ in },
        setAppActive: @escaping (Bool) async -> Void = { _ in },
        disconnectConnection: @escaping () async -> Void = {},
        clearShutterState: @escaping () async -> Void = {},
        clearStoredData: @escaping () async -> Void = {},
        deviceByID: @escaping (String) async -> DeviceRecord? = { _ in nil }
    ) -> RootTabStore.Dependencies {
        RootTabStore.Dependencies(
            log: log,
            preparePersistence: preparePersistence,
            decodeMessages: decodeMessages,
            applyMessage: applyMessage,
            sendText: sendText,
            setAppActive: setAppActive,
            disconnectConnection: disconnectConnection,
            clearShutterState: clearShutterState,
            clearStoredData: clearStoredData,
            deviceByID: deviceByID
        )
    }
}
