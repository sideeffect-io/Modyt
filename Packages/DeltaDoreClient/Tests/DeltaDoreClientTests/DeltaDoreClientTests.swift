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

@Test func deltaDoreClient_renewStoredConnectionIfNeededUpgradesRemoteToLocal() async throws {
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
            case .forceLocal, .auto:
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
    #expect(await recorder.labels() == ["forceRemote", "forceLocal"])
}

@Test func deltaDoreClient_renewStoredConnectionIfNeededKeepsAliveRemoteConnectionWhenLocalFails() async throws {
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
    let result = try await client.renewStoredConnectionIfNeeded()

    // Then
    #expect(result == .unchanged)
    #expect(await client.currentConnectionMode() == .remote(host: "mediation.tydom.com"))
    #expect(await recorder.labels() == ["forceRemote", "forceLocal"])
}

@Test func deltaDoreClient_renewStoredConnectionIfNeededKeepsCurrentRemoteWhenForceLocalFallsBackToRemote() async throws {
    // Given
    let currentRemoteConnection = makeConnection(mode: .remote(host: "current.tydom.com"))
    let fallbackRemoteConnection = makeConnection(mode: .remote(host: "fallback.tydom.com"))
    let recorder = StoredModeRecorder()
    let dependencies = DeltaDoreClient.Dependencies(
        inspectFlow: { .connectWithStoredCredentials },
        connectStored: { options in
            await recorder.record(options.mode)
            switch options.mode {
            case .forceRemote:
                return DeltaDoreClient.ConnectionSession(connection: currentRemoteConnection)
            case .forceLocal:
                return DeltaDoreClient.ConnectionSession(connection: fallbackRemoteConnection)
            case .auto:
                throw TestFailure.unexpectedAutoReconnect
            }
        },
        connectNew: { _, _ in
            DeltaDoreClient.ConnectionSession(connection: currentRemoteConnection)
        },
        listSites: { _ in [] },
        listSitesPayload: { _ in Data() },
        clearStoredData: {},
        probeConnection: { connection, _ in
            await connection.mode() == .remote(host: "current.tydom.com")
        }
    )
    let client = DeltaDoreClient(dependencies: dependencies)
    _ = try await client.connectWithStoredCredentials(options: .init(mode: .forceRemote))

    // When
    let result = try await client.renewStoredConnectionIfNeeded()

    // Then
    #expect(result == .unchanged)
    #expect(await client.currentConnectionMode() == .remote(host: "current.tydom.com"))
    #expect(await recorder.labels() == ["forceRemote", "forceLocal"])
}

@Test func deltaDoreClient_renewStoredConnectionIfNeededFallsBackToAutoWhenCurrentConnectionIsDead() async throws {
    // Given
    let remoteConnection = makeConnection(mode: .remote(host: "mediation.tydom.com"))
    let recoveredConnection = makeConnection(mode: .local(host: "192.168.1.20"))
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
                return DeltaDoreClient.ConnectionSession(connection: recoveredConnection)
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
    #expect(await client.currentConnectionMode() == .local(host: "192.168.1.20"))
    #expect(await recorder.labels() == ["forceRemote", "forceLocal", "auto"])
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
    case unexpectedAutoReconnect
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
