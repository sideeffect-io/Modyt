import Foundation
import Testing
@testable import DeltaDoreClient

@Test func deltaDoreClient_connectWithStoredCredentialsInvokesDependency() async throws {
    // Given
    let (stream, continuation) = AsyncStream<Void>.makeStream()
    let config = TydomConnection.Configuration(
        mode: .local(host: "192.168.1.10"),
        mac: "AA:BB:CC:DD:EE:FF",
        password: "pass"
    )
    let connection = TydomConnection(configuration: config)
    let dependencies = DeltaDoreClient.Dependencies(
        inspectFlow: { .connectWithStoredCredentials },
        connectStored: { _ in
            continuation.yield(())
            continuation.finish()
            return DeltaDoreClient.ConnectionSession(connection: connection)
        },
        connectNew: { _, _ in
            return DeltaDoreClient.ConnectionSession(connection: connection)
        },
        listSites: { _ in [] },
        listSitesPayload: { _ in Data() },
        clearStoredData: {},
        probeConnection: { _, _ in false }
    )
    let client = DeltaDoreClient(dependencies: dependencies)

    // When
    _ = try await client.connectWithStoredCredentials(options: .init(mode: .auto))

    // Then
    var iterator = stream.makeAsyncIterator()
    let signal: Void? = await iterator.next()
    #expect(signal != nil)
}

@Test func deltaDoreClient_connectWithNewCredentialsInvokesDependency() async throws {
    // Given
    let (stream, continuation) = AsyncStream<Void>.makeStream()
    let config = TydomConnection.Configuration(
        mode: .remote(host: "mediation.tydom.com"),
        mac: "AA:BB:CC:DD:EE:FF",
        password: "pass"
    )
    let connection = TydomConnection(configuration: config)
    let dependencies = DeltaDoreClient.Dependencies(
        inspectFlow: { .connectWithNewCredentials },
        connectStored: { _ in
            return DeltaDoreClient.ConnectionSession(connection: connection)
        },
        connectNew: { _, _ in
            continuation.yield(())
            continuation.finish()
            return DeltaDoreClient.ConnectionSession(connection: connection)
        },
        listSites: { _ in [] },
        listSitesPayload: { _ in Data() },
        clearStoredData: {},
        probeConnection: { _, _ in false }
    )
    let client = DeltaDoreClient(dependencies: dependencies)

    // When
    let credentials = TydomConnection.CloudCredentials(email: "user@example.com", password: "secret")
    _ = try await client.connectWithNewCredentials(options: .init(mode: .auto(cloudCredentials: credentials)))

    // Then
    var iterator = stream.makeAsyncIterator()
    let signal: Void? = await iterator.next()
    #expect(signal != nil)
}

@Test func storedResolverOptions_autoUsesFreshValidatedLocalDiscovery() {
    let options = makeStoredResolverOptions(for: .auto)

    #expect(options.mode == .auto)
    #expect(options.timings == .storedLocalPreferredFlow)
    #expect(options.preferFreshLocalDiscovery)
    #expect(!options.allowUnvalidatedLocalFallback)
}

@Test func validationTimeout_usesFullConfiguredTimeoutForNominalLocalConnection() {
    let configuration = TydomConnection.Configuration(
        mode: .local(host: "192.168.1.10"),
        mac: "AA:BB:CC:DD:EE:FF",
        password: "pass",
        timeout: 10.0
    )

    #expect(validationTimeout(for: configuration) == 10.0)
}

@Test func validationTimeout_keepsMinimumProbeBudget() {
    let configuration = TydomConnection.Configuration(
        mode: .local(host: "192.168.1.10"),
        mac: "AA:BB:CC:DD:EE:FF",
        password: "pass",
        timeout: 0.1
    )

    #expect(validationTimeout(for: configuration) == 0.5)
}

@Test func deltaDoreClient_renewStoredConnectionIfNeededKeepsHealthyLocalConnection() async throws {
    // Given
    let localConnection = makeConnection(mode: .local(host: "192.168.1.10"))
    let recorder = StoredModeRecorder()
    let dependencies = DeltaDoreClient.Dependencies(
        inspectFlow: { .connectWithStoredCredentials },
        connectStored: { options in
            await recorder.record(options.mode)
            switch options.mode {
            case .forceRemote:
                throw TestFailure.unexpectedRemoteReconnect
            case .forceLocal:
                return DeltaDoreClient.ConnectionSession(connection: localConnection)
            case .auto:
                throw TestFailure.unexpectedAutoReconnect
            }
        },
        connectNew: { _, _ in
            DeltaDoreClient.ConnectionSession(connection: localConnection)
        },
        listSites: { _ in [] },
        listSitesPayload: { _ in Data() },
        clearStoredData: {},
        probeConnection: { connection, _ in
            await connection.mode() == .local(host: "192.168.1.10")
        }
    )
    let client = DeltaDoreClient(dependencies: dependencies)
    _ = try await client.connectWithStoredCredentials(options: .init(mode: .forceLocal))

    // When
    let result = try await client.renewStoredConnectionIfNeeded()

    // Then
    #expect(result == .unchanged)
    #expect(await client.currentConnectionMode() == .local(host: "192.168.1.10"))
    #expect(await recorder.labels() == ["forceLocal"])
}

@Test func deltaDoreClient_renewStoredConnectionIfNeededPromotesHealthyRemoteConnectionToLocalWhenPreferred() async throws {
    // Given
    let remoteConnection = makeConnection(mode: .remote(host: "mediation.tydom.com"))
    let localConnection = makeConnection(mode: .local(host: "192.168.1.10"))
    let recorder = StoredModeRecorder()
    let dependencies = DeltaDoreClient.Dependencies(
        inspectFlow: { .connectWithStoredCredentials },
        connectStored: { options in
            await recorder.record(options.mode)
            switch options.mode {
            case .forceRemote:
                return DeltaDoreClient.ConnectionSession(connection: remoteConnection)
            case .forceLocal:
                throw TestFailure.unexpectedLocalReconnect
            case .auto:
                return DeltaDoreClient.ConnectionSession(connection: localConnection)
            }
        },
        connectNew: { _, _ in
            DeltaDoreClient.ConnectionSession(connection: remoteConnection)
        },
        listSites: { _ in [] },
        listSitesPayload: { _ in Data() },
        clearStoredData: {},
        probeConnection: { connection, _ in
            await connection.mode() == .remote(host: "mediation.tydom.com")
        }
    )
    let client = DeltaDoreClient(dependencies: dependencies)
    _ = try await client.connectWithStoredCredentials(options: .init(mode: .forceRemote))

    // When
    let result = try await client.renewStoredConnectionIfNeeded()

    // Then
    #expect(result == .reconnected)
    #expect(await client.currentConnectionMode() == .local(host: "192.168.1.10"))
    #expect(await recorder.labels() == ["forceRemote", "auto"])
}

@Test func deltaDoreClient_renewStoredConnectionIfNeededKeepsHealthyRemoteConnectionWhenLocalIsNotPreferred() async throws {
    // Given
    let remoteConnection = makeConnection(mode: .remote(host: "mediation.tydom.com"))
    let recorder = StoredModeRecorder()
    let dependencies = DeltaDoreClient.Dependencies(
        inspectFlow: { .connectWithStoredCredentials },
        connectStored: { options in
            await recorder.record(options.mode)
            switch options.mode {
            case .forceRemote:
                return DeltaDoreClient.ConnectionSession(connection: remoteConnection)
            case .forceLocal:
                throw TestFailure.unexpectedLocalReconnect
            case .auto:
                throw TestFailure.unexpectedAutoReconnect
            }
        },
        connectNew: { _, _ in
            DeltaDoreClient.ConnectionSession(connection: remoteConnection)
        },
        listSites: { _ in [] },
        listSitesPayload: { _ in Data() },
        clearStoredData: {},
        probeConnection: { connection, _ in
            await connection.mode() == .remote(host: "mediation.tydom.com")
        }
    )
    let client = DeltaDoreClient(dependencies: dependencies)
    _ = try await client.connectWithStoredCredentials(options: .init(mode: .forceRemote))

    // When
    let result = try await client.renewStoredConnectionIfNeeded(
        preferLocal: false
    )

    // Then
    #expect(result == .unchanged)
    #expect(await client.currentConnectionMode() == .remote(host: "mediation.tydom.com"))
    #expect(await recorder.labels() == ["forceRemote"])
}

@Test func deltaDoreClient_renewStoredConnectionIfNeededReconnectsDeadRemoteLocally() async throws {
    // Given
    let remoteConnection = makeConnection(mode: .remote(host: "mediation.tydom.com"))
    let localConnection = makeConnection(mode: .local(host: "192.168.1.10"))
    let recorder = StoredModeRecorder()
    let dependencies = DeltaDoreClient.Dependencies(
        inspectFlow: { .connectWithStoredCredentials },
        connectStored: { options in
            await recorder.record(options.mode)
            switch options.mode {
            case .forceRemote:
                return DeltaDoreClient.ConnectionSession(connection: remoteConnection)
            case .forceLocal:
                throw TestFailure.unexpectedLocalReconnect
            case .auto:
                return DeltaDoreClient.ConnectionSession(connection: localConnection)
            }
        },
        connectNew: { _, _ in
            DeltaDoreClient.ConnectionSession(connection: remoteConnection)
        },
        listSites: { _ in [] },
        listSitesPayload: { _ in Data() },
        clearStoredData: {},
        probeConnection: { _, _ in false }
    )
    let client = DeltaDoreClient(dependencies: dependencies)
    _ = try await client.connectWithStoredCredentials(options: .init(mode: .forceRemote))

    // When
    let result = try await client.renewStoredConnectionIfNeeded()

    // Then
    #expect(result == .reconnected)
    #expect(await client.currentConnectionMode() == .local(host: "192.168.1.10"))
    #expect(await recorder.labels() == ["forceRemote", "auto"])
}

@Test func deltaDoreClient_renewStoredConnectionIfNeededCanSkipLivenessProbe() async throws {
    // Given
    let currentRemoteConnection = makeConnection(mode: .remote(host: "current.tydom.com"))
    let recoveredLocalConnection = makeConnection(mode: .local(host: "192.168.1.10"))
    let modeRecorder = StoredModeRecorder()
    let probeRecorder = ProbeRecorder()
    let dependencies = DeltaDoreClient.Dependencies(
        inspectFlow: { .connectWithStoredCredentials },
        connectStored: { options in
            await modeRecorder.record(options.mode)
            switch options.mode {
            case .forceRemote:
                return DeltaDoreClient.ConnectionSession(connection: currentRemoteConnection)
            case .forceLocal:
                throw TestFailure.unexpectedLocalReconnect
            case .auto:
                return DeltaDoreClient.ConnectionSession(connection: recoveredLocalConnection)
            }
        },
        connectNew: { _, _ in
            DeltaDoreClient.ConnectionSession(connection: currentRemoteConnection)
        },
        listSites: { _ in [] },
        listSitesPayload: { _ in Data() },
        clearStoredData: {},
        probeConnection: { _, _ in
            await probeRecorder.record()
            return false
        }
    )
    let client = DeltaDoreClient(dependencies: dependencies)
    _ = try await client.connectWithStoredCredentials(options: .init(mode: .forceRemote))

    // When
    let result = try await client.renewStoredConnectionIfNeeded(
        skipLivenessProbe: true
    )

    // Then
    #expect(result == .reconnected)
    #expect(await client.currentConnectionMode() == .local(host: "192.168.1.10"))
    #expect(await modeRecorder.labels() == ["forceRemote", "auto"])
    #expect(await probeRecorder.count() == 0)
}

@Test func deltaDoreClient_renewStoredConnectionIfNeededFallsBackToRemoteWhenDeadConnectionCannotReconnectLocally() async throws {
    // Given
    let currentRemoteConnection = makeConnection(mode: .remote(host: "current.tydom.com"))
    let recoveredRemoteConnection = makeConnection(mode: .remote(host: "recovered.tydom.com"))
    let recorder = StoredModeRecorder()
    let dependencies = DeltaDoreClient.Dependencies(
        inspectFlow: { .connectWithStoredCredentials },
        connectStored: { options in
            await recorder.record(options.mode)
            switch options.mode {
            case .forceRemote:
                return DeltaDoreClient.ConnectionSession(connection: currentRemoteConnection)
            case .forceLocal:
                throw TestFailure.localUnavailable
            case .auto:
                return DeltaDoreClient.ConnectionSession(connection: recoveredRemoteConnection)
            }
        },
        connectNew: { _, _ in
            DeltaDoreClient.ConnectionSession(connection: currentRemoteConnection)
        },
        listSites: { _ in [] },
        listSitesPayload: { _ in Data() },
        clearStoredData: {},
        probeConnection: { _, _ in false }
    )
    let client = DeltaDoreClient(dependencies: dependencies)
    _ = try await client.connectWithStoredCredentials(options: .init(mode: .forceRemote))

    // When
    let result = try await client.renewStoredConnectionIfNeeded()

    // Then
    #expect(result == .reconnected)
    #expect(await client.currentConnectionMode() == .remote(host: "recovered.tydom.com"))
    #expect(await recorder.labels() == ["forceRemote", "auto"])
}

@Test func deltaDoreClient_renewStoredConnectionIfNeededReconnectsLocallyWhenNoCurrentConnectionExists() async throws {
    // Given
    let localConnection = makeConnection(mode: .local(host: "192.168.1.10"))
    let recorder = StoredModeRecorder()
    let dependencies = DeltaDoreClient.Dependencies(
        inspectFlow: { .connectWithStoredCredentials },
        connectStored: { options in
            await recorder.record(options.mode)
            switch options.mode {
            case .forceRemote:
                throw TestFailure.unexpectedRemoteReconnect
            case .forceLocal:
                throw TestFailure.unexpectedLocalReconnect
            case .auto:
                return DeltaDoreClient.ConnectionSession(connection: localConnection)
            }
        },
        connectNew: { _, _ in
            DeltaDoreClient.ConnectionSession(connection: localConnection)
        },
        listSites: { _ in [] },
        listSitesPayload: { _ in Data() },
        clearStoredData: {},
        probeConnection: { _, _ in false }
    )
    let client = DeltaDoreClient(dependencies: dependencies)

    // When
    let result = try await client.renewStoredConnectionIfNeeded()

    // Then
    #expect(result == .reconnected)
    #expect(await client.currentConnectionMode() == .local(host: "192.168.1.10"))
    #expect(await recorder.labels() == ["auto"])
}

@Test func deltaDoreClient_renewStoredConnectionIfNeededFallsBackToRemoteWhenNoCurrentConnectionExists() async throws {
    // Given
    let remoteConnection = makeConnection(mode: .remote(host: "mediation.tydom.com"))
    let recorder = StoredModeRecorder()
    let dependencies = DeltaDoreClient.Dependencies(
        inspectFlow: { .connectWithStoredCredentials },
        connectStored: { options in
            await recorder.record(options.mode)
            switch options.mode {
            case .forceRemote:
                return DeltaDoreClient.ConnectionSession(connection: remoteConnection)
            case .forceLocal:
                throw TestFailure.localUnavailable
            case .auto:
                return DeltaDoreClient.ConnectionSession(connection: remoteConnection)
            }
        },
        connectNew: { _, _ in
            DeltaDoreClient.ConnectionSession(connection: remoteConnection)
        },
        listSites: { _ in [] },
        listSitesPayload: { _ in Data() },
        clearStoredData: {},
        probeConnection: { _, _ in false }
    )
    let client = DeltaDoreClient(dependencies: dependencies)

    // When
    let result = try await client.renewStoredConnectionIfNeeded()

    // Then
    #expect(result == .reconnected)
    #expect(await client.currentConnectionMode() == .remote(host: "mediation.tydom.com"))
    #expect(await recorder.labels() == ["auto"])
}

private func makeConnection(mode: TydomConnection.Configuration.Mode) -> TydomConnection {
    TydomConnection(
        configuration: .init(
            mode: mode,
            mac: "AA:BB:CC:DD:EE:FF",
            password: "pass"
        )
    )
}

private enum TestFailure: Error {
    case localUnavailable
    case unexpectedRemoteReconnect
    case unexpectedAutoReconnect
    case unexpectedLocalReconnect
}

private actor StoredModeRecorder {
    private var recorded: [String] = []

    func record(_ mode: DeltaDoreClient.StoredCredentialsFlowOptions.Mode) {
        switch mode {
        case .auto:
            recorded.append("auto")
        case .forceLocal:
            recorded.append("forceLocal")
        case .forceRemote:
            recorded.append("forceRemote")
        }
    }

    func labels() -> [String] {
        recorded
    }
}

private actor ProbeRecorder {
    private var value = 0

    func record() {
        value += 1
    }

    func count() -> Int {
        value
    }
}
