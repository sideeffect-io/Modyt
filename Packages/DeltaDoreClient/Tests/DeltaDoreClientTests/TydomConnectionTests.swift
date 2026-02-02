import Foundation
import Testing

@testable import DeltaDoreClient

@Test func connection_sendThrowsWhenNotConnected() async {
    // Given
    let connection = makeConnection()

    // When / Then
    do {
        try await connection.send(Data("ping".utf8))
        #expect(Bool(false), "Expected notConnected error")
    } catch {
        guard let connectionError = error as? TydomConnection.ConnectionError else {
            #expect(Bool(false), "Expected ConnectionError, got \\(error)")
            return
        }
        #expect(connectionError == .notConnected)
    }
}

@Test func connection_sendTextThrowsWhenNotConnected() async {
    // Given
    let connection = makeConnection()

    // When / Then
    do {
        try await connection.send(text: "ping")
        #expect(Bool(false), "Expected notConnected error")
    } catch {
        guard let connectionError = error as? TydomConnection.ConnectionError else {
            #expect(Bool(false), "Expected ConnectionError, got \\(error)")
            return
        }
        #expect(connectionError == .notConnected)
    }
}

@Test func connection_pingThrowsWhenNotConnected() async {
    // Given
    let connection = makeConnection()

    // When / Then
    do {
        _ = try await connection.pingAndWaitForResponse(timeout: 0.1)
        #expect(Bool(false), "Expected notConnected error")
    } catch {
        guard let connectionError = error as? TydomConnection.ConnectionError else {
            #expect(Bool(false), "Expected ConnectionError, got \\(error)")
            return
        }
        #expect(connectionError == .notConnected)
    }
}

@Test func connection_setAppActiveUpdatesState() async {
    // Given
    let connection = makeConnection()

    // When
    await connection.setAppActive(false)

    // Then
    #expect(await connection.isAppActive() == false)

    // When
    await connection.setAppActive(true)

    // Then
    #expect(await connection.isAppActive() == true)
}

@Test func connection_disconnectTriggersOnDisconnect() async {
    // Given
    let config = makeConfiguration()
    let signal = DisconnectSignal()
    let stream = await signal.makeStream()
    let connection = makeConnection(configuration: config, onDisconnect: {
        await signal.signal()
    })

    // When
    await connection.disconnect()

    // Then
    let result: Void? = await firstValue(from: stream, timeout: 1.0)
    #expect(result != nil)
}

private func makeConnection(
    configuration: TydomConnection.Configuration = makeConfiguration(),
    onDisconnect: @escaping @Sendable () async -> Void = {}
) -> TydomConnection {
    let dependencies = TydomConnection.Dependencies(
        makeSession: { _, _, _ in URLSession(configuration: .ephemeral) },
        randomBytes: { _ in [UInt8](repeating: 0, count: 16) },
        now: { Date() },
        fetchGatewayPassword: { _, _, _ in "password" },
        invalidateSession: { _ in },
        onDisconnect: onDisconnect
    )
    return TydomConnection(configuration: configuration, dependencies: dependencies)
}

private func makeConfiguration() -> TydomConnection.Configuration {
    TydomConnection.Configuration(
        mode: .local(host: "192.168.1.10"),
        mac: "AA:BB:CC:DD:EE:FF",
        password: "secret",
        allowInsecureTLS: true,
        timeout: 1.0,
        polling: .init(intervalSeconds: 0, onlyWhenActive: false),
        keepAlive: .init(intervalSeconds: 0, onlyWhenActive: false)
    )
}

private func firstValue<T: Sendable>(
    from stream: AsyncStream<T>,
    timeout: TimeInterval
) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask {
            var iterator = stream.makeAsyncIterator()
            return await iterator.next()
        }
        group.addTask {
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            return nil
        }
        let value = await group.next() ?? nil
        group.cancelAll()
        return value
    }
}

private actor DisconnectSignal {
    private var continuation: AsyncStream<Void>.Continuation?

    func makeStream() -> AsyncStream<Void> {
        AsyncStream { continuation in
            self.continuation = continuation
        }
    }

    func signal() {
        continuation?.yield(())
    }
}
