import DeltaDoreClient

struct MainStoreFactory: Sendable {
    private let makeStore: @MainActor @Sendable () -> MainStore

    init(make: @escaping @MainActor @Sendable () -> MainStore) {
        self.makeStore = make
    }

    @MainActor
    func make() -> MainStore {
        makeStore()
    }

    static func live(dependencyBag: DependencyBag) -> Self {
        let gatewayClient = dependencyBag.gatewayClient
        let messageRouter = dependencyBag.localStorageDatasources.tydomMessageRepositoryRouter
        let runtime = MainRuntime(
            gatewayClient: gatewayClient,
            router: messageRouter
        )

        return Self {
            MainStore(
                handleGatewayMessages: .init(
                    handleGatewayMessages: { await runtime.handleGatewayMessages() }
                ),
                disconnect: .init(
                    disconnect: { await runtime.disconnect() }
                ),
                setAppInactive: .init(
                    setAppInactive: { await runtime.setAppInactive() }
                ),
                setAppActive: .init(
                    setAppActive: { await runtime.setAppActive() }
                ),
                checkGatewayConnection: .init(
                    checkGatewayConnection: { await runtime.checkGatewayConnection() }
                ),
                reconnectToGateway: .init(
                    reconnectToGateway: { await runtime.reconnectToGateway() }
                )
            )
        }
    }
}

struct MainGatewayDataRequestPipeline: Sendable {
    struct Request: Sendable {
        let label: String
        let makeCommand: @Sendable (String) -> TydomCommand
    }

    static let defaultRequests: [Request] = [
        Request(label: "configs-file", makeCommand: TydomCommand.configsFile),
        Request(label: "devices-meta", makeCommand: TydomCommand.devicesMeta),
        Request(label: "devices-cmeta", makeCommand: TydomCommand.devicesCmeta),
        Request(label: "devices-data", makeCommand: TydomCommand.devicesData),
        Request(label: "scenarios-file", makeCommand: TydomCommand.scenariosFile),
        Request(label: "groups-file", makeCommand: TydomCommand.groupsFile)
    ]

    let requests: [Request]
    let makeTransactionID: @Sendable () async -> String
    let sendText: @Sendable (String) async throws -> Void

    func run() async throws {
        for request in requests {
            try Task.checkCancellation()
            let transactionId = await makeTransactionID()
            let command = request.makeCommand(transactionId)
            try await sendText(command.request)
        }
    }
}

struct MainMessageStreamObservationState: Sendable, Equatable {
    private(set) var activeTaskID: Int?

    mutating func register(taskID: Int) -> Bool {
        guard activeTaskID == nil else { return false }
        activeTaskID = taskID
        return true
    }

    mutating func finish(taskID: Int) -> Bool {
        guard activeTaskID == taskID else { return false }
        activeTaskID = nil
        return true
    }

    mutating func cancel() {
        activeTaskID = nil
    }
}

actor MainRuntime {
    private let gatewayClient: DeltaDoreClient
    private let router: TydomMessageRepositoryRouter
    private let log: @Sendable (String) -> Void

    private var messageStreamTask: Task<Void, Never>?
    private var messageStreamObservation = MainMessageStreamObservationState()
    private var nextMessageStreamTaskID: Int = 0

    init(
        gatewayClient: DeltaDoreClient,
        router: TydomMessageRepositoryRouter,
        log: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.gatewayClient = gatewayClient
        self.router = router
        self.log = log
    }

    deinit {
        messageStreamTask?.cancel()
    }

    func handleGatewayMessages() async -> MainEvent {
        do {
            try await prepareGatewayHandling(restartStream: false)
            return .gatewayHandlingWasSuccessful
        } catch {
            if error is CancellationError {
                return .gatewayHandlingWasAFailure
            }
            log("MainRuntime handleGatewayMessages failed error=\(error)")
            return .gatewayHandlingWasAFailure
        }
    }

    func disconnect() async {
        cancelMessageStream()
        await router.clearRepositories()
        await gatewayClient.disconnectCurrentConnection()
        await gatewayClient.clearStoredData()
    }

    func setAppInactive() async {
        await gatewayClient.setCurrentConnectionAppActive(false)
    }

    func setAppActive() async {
        await gatewayClient.setCurrentConnectionAppActive(true)
    }

    func checkGatewayConnection() async -> MainEvent? {
        let isAlive = await gatewayClient.isCurrentConnectionAlive(timeout: 2.0)
        if isAlive {
            if let mode = await gatewayClient.currentConnectionMode() {
                switch mode {
                case .local:
                    await gatewayClient.setCurrentConnectionAppActive(true)
                    return nil
                case .remote:
                    cancelMessageStream()
                    return .reconnectionWasRequested
                }
            }
        }

        cancelMessageStream()
        return .reconnectionWasRequested
    }

    func reconnectToGateway() async -> MainEvent {
        do {
            _ = try await gatewayClient.renewStoredConnectionIfNeeded(
                preferLocal: true,
                livenessTimeout: 2.0,
                skipLivenessProbe: true
            )
            try await prepareGatewayHandling(restartStream: true)
            await gatewayClient.setCurrentConnectionAppActive(true)
            return .reconnectionWasSuccessful
        } catch {
            if error is CancellationError {
                return .reconnectionWasAFailure
            }
            log("MainRuntime reconnectToGateway failed error=\(error)")
            return .reconnectionWasAFailure
        }
    }

    private func requestGatewayData() async throws {
        let pipeline = MainGatewayDataRequestPipeline(
            requests: MainGatewayDataRequestPipeline.defaultRequests,
            makeTransactionID: {
                TydomCommand.defaultTransactionId()
            },
            sendText: { text in
                try await self.gatewayClient.send(text: text)
            }
        )
        try await pipeline.run()
    }

    private func prepareGatewayHandling(restartStream: Bool) async throws {
        try await router.startIfNeeded()
        if restartStream {
            cancelMessageStream()
        }
        startGatewayMessagesHandling()
        try await requestGatewayData()
    }

    private func startGatewayMessagesHandling() {
        let taskID = nextMessageStreamTaskID
        nextMessageStreamTaskID += 1
        guard messageStreamObservation.register(taskID: taskID) else { return }

        messageStreamTask = Task { [gatewayClient, router, log, weak self] in
            let stream = await gatewayClient.decodedMessages(logger: log)
            for await message in stream {
                guard !Task.isCancelled else { break }
                await router.ingest(message)
            }
            await self?.messageStreamDidTerminate(taskID: taskID)
        }
    }

    private func messageStreamDidTerminate(taskID: Int) {
        guard messageStreamObservation.finish(taskID: taskID) else { return }
        messageStreamTask = nil
    }

    private func cancelMessageStream() {
        messageStreamTask?.cancel()
        messageStreamTask = nil
        messageStreamObservation.cancel()
    }
}
