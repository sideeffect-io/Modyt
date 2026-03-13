import Foundation
import Testing
@testable import DeltaDoreClient
@testable import MoDyt

@MainActor
struct AuthenticationStoreIntegrationTests {
    @Test
    func storedCredentialsAuthenticateWhenNominalSilentReconnectSucceedsLocally() async throws {
        let recorder = AuthenticationStoredModeRecorder()
        let gatewayClient = makeGatewayClient(recorder: recorder) { mode in
            switch mode {
            case .auto:
                return makeAuthenticationTestConnection(mode: .local(host: "192.168.1.20"))
            case .forceLocal, .forceRemote:
                throw AuthenticationTestFailure.unexpectedForcedReconnect
            }
        }
        let store = makeStore(gatewayClient: gatewayClient)
        let delegate = AuthenticationDelegateRecorder()
        store.onDelegateEvent = { event in
            if case .authenticated = event {
                delegate.recordAuthenticated()
            }
        }

        store.start()

        #expect(await testWaitUntil(cycles: 200) { delegate.authenticatedCount == 1 })
        #expect(store.state.phase == .connecting)
        #expect(await recorder.labels() == ["auto"])
    }

    @Test
    func storedCredentialsAuthenticateWhenNominalSilentReconnectFallsBackToRemote() async throws {
        let recorder = AuthenticationStoredModeRecorder()
        let gatewayClient = makeGatewayClient(recorder: recorder) { mode in
            switch mode {
            case .auto:
                return makeAuthenticationTestConnection(mode: .remote(host: "mediation.tydom.com"))
            case .forceLocal, .forceRemote:
                throw AuthenticationTestFailure.unexpectedForcedReconnect
            }
        }
        let store = makeStore(gatewayClient: gatewayClient)
        let delegate = AuthenticationDelegateRecorder()
        store.onDelegateEvent = { event in
            if case .authenticated = event {
                delegate.recordAuthenticated()
            }
        }

        store.start()

        #expect(await testWaitUntil(cycles: 200) { delegate.authenticatedCount == 1 })
        #expect(store.state.phase == .connecting)
        #expect(await recorder.labels() == ["auto"])
    }

    @Test
    func storedCredentialsFailureSurfacesError() async throws {
        let recorder = AuthenticationStoredModeRecorder()
        let gatewayClient = makeGatewayClient(recorder: recorder) { mode in
            switch mode {
            case .auto:
                throw AuthenticationTestFailure.reconnectUnavailable
            case .forceLocal, .forceRemote:
                throw AuthenticationTestFailure.unexpectedForcedReconnect
            }
        }
        let store = makeStore(gatewayClient: gatewayClient)
        let delegate = AuthenticationDelegateRecorder()
        store.onDelegateEvent = { event in
            if case .authenticated = event {
                delegate.recordAuthenticated()
            }
        }

        store.start()

        #expect(await testWaitUntil(cycles: 1200) {
            if case .error = store.state.phase {
                return true
            }
            return false
        })
        #expect(delegate.authenticatedCount == 0)
        #expect(await recorder.labels() == ["auto"])
    }

    private func makeStore(gatewayClient: DeltaDoreClient) -> AuthenticationStore {
        let dependencyBag = DependencyBag(
            localStorageDatasources: makeLocalStorageDatasources(
                databasePath: testTemporarySQLitePath("AuthenticationStoreIntegrationTests")
            ),
            gatewayClient: gatewayClient
        )
        let factory = AuthenticationStoreFactory.live(dependencyBag: dependencyBag)
        return factory.make()
    }

    private func makeGatewayClient(
        recorder: AuthenticationStoredModeRecorder,
        connectStored: @escaping @Sendable (DeltaDoreClient.StoredCredentialsFlowOptions.Mode) async throws -> TydomConnection
    ) -> DeltaDoreClient {
        let dependencies = DeltaDoreClient.Dependencies(
            inspectFlow: { .connectWithStoredCredentials },
            connectStored: { options in
                await recorder.record(options.mode)
                return DeltaDoreClient.ConnectionSession(
                    connection: try await connectStored(options.mode)
                )
            },
            connectNew: { _, _ in
                DeltaDoreClient.ConnectionSession(
                    connection: makeAuthenticationTestConnection(mode: .remote(host: "mediation.tydom.com"))
                )
            },
            listSites: { _ in [] },
            listSitesPayload: { _ in Data() },
            clearStoredData: {},
            probeConnection: { _, _ in false }
        )
        return DeltaDoreClient(dependencies: dependencies)
    }
}

@MainActor
private final class AuthenticationDelegateRecorder {
    private(set) var authenticatedCount = 0

    func recordAuthenticated() {
        authenticatedCount += 1
    }
}

private actor AuthenticationStoredModeRecorder {
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

private enum AuthenticationTestFailure: Error {
    case reconnectUnavailable
    case unexpectedForcedReconnect
}

private func makeAuthenticationTestConnection(
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
