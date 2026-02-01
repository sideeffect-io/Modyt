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
        clearStoredData: {}
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
        clearStoredData: {}
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
