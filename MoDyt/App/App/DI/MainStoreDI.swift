import DeltaDoreClient
import SwiftUI

enum MainStoreDependencyFactory {
    static func make(
        dependencyBag: DependencyBag = .production
    ) -> MainStore.Dependencies {
        let gatewayClient = dependencyBag.gatewayClient
        let messageRouter = dependencyBag.localStorageDatasources.tydomMessageRepositoryRouter
        let runtime = MainRuntime(
            gatewayClient: gatewayClient,
            router: messageRouter
        )

        return .init(
            handleGatewayMessages: { await runtime.handleGatewayMessages() },
            disconnect: { await runtime.disconnect() },
            setAppInactive: { await runtime.setAppInactive() },
            setAppActive: { await runtime.setAppActive() },
            checkGatewayConnection: { await runtime.checkGatewayConnection() },
            reconnectToGateway: { await runtime.reconnectToGateway() }
        )
    }
}

extension EnvironmentValues {
    @Entry var mainStoreDependencies: MainStore.Dependencies =
        MainStoreDependencyFactory.make()
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

actor MainRuntime {
    private let gatewayClient: DeltaDoreClient
    private let router: TydomMessageRepositoryRouter
    private let log: @Sendable (String) -> Void

    private var messageStreamTask: Task<Void, Never>?

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
            try await router.startIfNeeded()
            startGatewayMessagesHandling()
            try await requestGatewayData()
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
            await gatewayClient.setCurrentConnectionAppActive(true)
            return nil
        } else {
            cancelMessageStream()
        }
        return .reconnectionWasRequested
    }

    func reconnectToGateway() async -> MainEvent {
        do {
            _ = try await gatewayClient.connectWithStoredCredentials(options: .init(mode: .auto))
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

    private func startGatewayMessagesHandling() {
        guard messageStreamTask == nil else { return }

        messageStreamTask = Task { [gatewayClient, router, log, weak self] in
            let stream = await gatewayClient.decodedMessages(logger: log)
            for await message in stream {
                guard !Task.isCancelled else { break }
                await router.ingest(message)
            }
            await self?.messageStreamDidTerminate()
        }
    }

    private func messageStreamDidTerminate() {
        messageStreamTask = nil
    }

    private func cancelMessageStream() {
        messageStreamTask?.cancel()
        messageStreamTask = nil
    }
}
