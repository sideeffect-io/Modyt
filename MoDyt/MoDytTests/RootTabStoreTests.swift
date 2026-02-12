import Testing
import DeltaDoreClient
@testable import MoDyt

@MainActor
struct RootTabStoreTests {
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
        messageStream.finish()

        #expect(await prepareCounter.value == 1)
        #expect(await appActiveRecorder.values == [true])

        let requests = await sendRecorder.values
        #expect(requests.count == 7)
        #expect(requests.contains(where: { $0.contains("GET /configs/file HTTP/1.1") }))
        #expect(requests.contains(where: { $0.contains("GET /devices/meta HTTP/1.1") }))
        #expect(requests.contains(where: { $0.contains("GET /devices/cmeta HTTP/1.1") }))
        #expect(requests.contains(where: { $0.contains("GET /devices/data HTTP/1.1") }))
        #expect(requests.contains(where: { $0.contains("GET /areas/data HTTP/1.1") }))
        #expect(requests.contains(where: { $0.contains("GET /scenarios/file HTTP/1.1") }))
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
        setAppActive: @escaping (Bool) async -> Void = { _ in }
    ) -> RootTabStore.Dependencies {
        RootTabStore.Dependencies(
            log: log,
            preparePersistence: preparePersistence,
            decodeMessages: decodeMessages,
            applyMessage: applyMessage,
            sendText: sendText,
            setAppActive: setAppActive
        )
    }
}
