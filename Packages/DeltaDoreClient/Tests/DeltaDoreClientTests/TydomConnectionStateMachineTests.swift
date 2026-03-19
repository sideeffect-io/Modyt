import Foundation
import Testing
@testable import DeltaDoreClient

@Test func stateMachine_missingCredentialsFails() async {
    // Given
    let state = TydomConnectionState(phase: .idle, override: .none, credentials: nil)

    // When
    let (next, actions) = TydomConnectionStateMachine.reduce(
        state: state,
        event: .credentialsLoaded(nil)
    )

    // Then
    #expect(next.phase == .failed)
    #expect(actions.contains(.connectRemote) == false)
}

@Test func stateMachine_cachedIPFailureTriggersDiscovery() async {
    // Given
    let credentials = TydomGatewayCredentials(
        mac: "AABBCCDDEEFF",
        password: "pass",
        cachedLocalIP: "192.168.1.10",
        updatedAt: Date()
    )
    let state = TydomConnectionState(phase: .tryingCachedIP, override: .none, credentials: credentials)

    // When
    let (next, actions) = TydomConnectionStateMachine.reduce(
        state: state,
        event: .cachedIPFailed("192.168.1.10")
    )

    // Then
    #expect(next.phase == .discoveringLocal)
    #expect(actions.contains(.discoverLocal(excludingHost: "192.168.1.10")))
}

@Test func stateMachine_autoUsesCachedIPBeforeDiscovery() async {
    // Given
    let credentials = TydomGatewayCredentials(
        mac: "AABBCCDDEEFF",
        password: "pass",
        cachedLocalIP: "192.168.1.10",
        updatedAt: Date()
    )
    let state = TydomConnectionState(
        phase: .loadingCredentials,
        override: .none,
        credentials: credentials
    )

    // When
    let (next, actions) = TydomConnectionStateMachine.reduce(
        state: state,
        event: .credentialsLoaded(credentials)
    )

    // Then
    #expect(next.phase == .tryingCachedIP)
    #expect(actions.contains(.tryCachedIP("192.168.1.10")))
    #expect(actions.contains(.discoverLocal(excludingHost: nil)) == false)
}

@Test func stateMachine_localFailureFallsBackToRemote() async {
    // Given
    let credentials = TydomGatewayCredentials(
        mac: "AABBCCDDEEFF",
        password: "pass",
        cachedLocalIP: "192.168.1.10",
        updatedAt: Date()
    )
    let state = TydomConnectionState(phase: .connectingLocal, override: .none, credentials: credentials)

    // When
    let (next, actions) = TydomConnectionStateMachine.reduce(
        state: state,
        event: .localConnectResult(success: false, host: nil, connection: nil)
    )

    // Then
    #expect(next.phase == .connectingRemote)
    #expect(actions.contains(.connectRemote))
}

@Test func stateMachine_overrideRemoteForcesRemote() async {
    // Given
    let credentials = TydomGatewayCredentials(
        mac: "AABBCCDDEEFF",
        password: "pass",
        cachedLocalIP: "192.168.1.10",
        updatedAt: Date()
    )
    let state = TydomConnectionState(phase: .loadingCredentials, override: .forceRemote, credentials: credentials)

    // When
    let (next, actions) = TydomConnectionStateMachine.reduce(
        state: state,
        event: .credentialsLoaded(credentials)
    )

    // Then
    #expect(next.phase == .connectingRemote)
    #expect(actions.contains(.connectRemote))
}

@Test func stateMachine_overrideLocalUsesDiscoveryWhenNoCache() async {
    // Given
    let credentials = TydomGatewayCredentials(
        mac: "AABBCCDDEEFF",
        password: "pass",
        cachedLocalIP: nil,
        updatedAt: Date()
    )
    let state = TydomConnectionState(phase: .loadingCredentials, override: .forceLocal, credentials: credentials)

    // When
    let (next, actions) = TydomConnectionStateMachine.reduce(
        state: state,
        event: .credentialsLoaded(credentials)
    )

    // Then
    #expect(next.phase == .discoveringLocal)
    #expect(actions.contains(.discoverLocal(excludingHost: nil)))
}

@Test func stateMachine_overrideLocalUsesCachedIPBeforeDiscovery() async {
    // Given
    let credentials = TydomGatewayCredentials(
        mac: "AABBCCDDEEFF",
        password: "pass",
        cachedLocalIP: "192.168.1.10",
        updatedAt: Date()
    )
    let state = TydomConnectionState(phase: .loadingCredentials, override: .forceLocal, credentials: credentials)

    // When
    let (next, actions) = TydomConnectionStateMachine.reduce(
        state: state,
        event: .credentialsLoaded(credentials)
    )

    // Then
    #expect(next.phase == .tryingCachedIP)
    #expect(actions.contains(.tryCachedIP("192.168.1.10")))
    #expect(actions.contains(.discoverLocal(excludingHost: nil)) == false)
}

@Test func stateMachine_overrideLocalFailsWhenDiscoveryFindsNoGateway() async {
    // Given
    let credentials = TydomGatewayCredentials(
        mac: "AABBCCDDEEFF",
        password: "pass",
        cachedLocalIP: nil,
        updatedAt: Date()
    )
    let state = TydomConnectionState(
        phase: .discoveringLocal,
        override: .forceLocal,
        credentials: credentials
    )

    // When
    let (next, actions) = TydomConnectionStateMachine.reduce(
        state: state,
        event: .localDiscoveryFound([])
    )

    // Then
    #expect(next.phase == .failed)
    #expect(next.lastError == "Local discovery failed")
    #expect(actions.contains(.connectRemote) == false)
}

@Test func stateMachine_overrideLocalFailsAfterLastLocalCandidateFails() async {
    // Given
    let credentials = TydomGatewayCredentials(
        mac: "AABBCCDDEEFF",
        password: "pass",
        cachedLocalIP: "192.168.1.10",
        updatedAt: Date()
    )
    let state = TydomConnectionState(
        phase: .connectingLocal,
        override: .forceLocal,
        credentials: credentials
    )

    // When
    let (next, actions) = TydomConnectionStateMachine.reduce(
        state: state,
        event: .localConnectResult(success: false, host: "192.168.1.10", connection: nil)
    )

    // Then
    #expect(next.phase == .failed)
    #expect(next.lastError == "Local connection failed")
    #expect(actions.contains(.connectRemote) == false)
}
