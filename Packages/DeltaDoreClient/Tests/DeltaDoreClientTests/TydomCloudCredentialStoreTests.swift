import Foundation
import Testing
@testable import DeltaDoreClient

@Test func cloudCredentialStore_saveLoadDeleteAll() async throws {
    // Given
    let store = TydomCloudCredentialStore.inMemory()
    let credentials = TydomConnection.CloudCredentials(
        email: "user@example.com",
        password: "secret"
    )

    // When
    try await store.save(credentials)
    let loaded = try await store.load()
    try await store.deleteAll()
    let deleted = try await store.load()

    // Then
    #expect(loaded?.email == credentials.email)
    #expect(loaded?.password == credentials.password)
    #expect(deleted == nil)
}

@Test func resolver_onDisconnectClearsStoredData() async throws {
    // Given
    let gatewayMac = "AA:BB:CC:DD:EE:FF"
    let credentials = TydomGatewayCredentials(
        mac: gatewayMac,
        password: "secret",
        cachedLocalIP: "192.168.1.10",
        updatedAt: Date()
    )
    let gatewayId = TydomMac.normalize(gatewayMac)
    let credentialStore = TydomGatewayCredentialStore.inMemory(initial: [
        gatewayId: credentials
    ])
    let gatewayMacStore = TydomGatewayMacStore.inMemory(initial: gatewayMac)
    let cloudCredentials = TydomConnection.CloudCredentials(
        email: "user@example.com",
        password: "secret"
    )
    let cloudCredentialStore = TydomCloudCredentialStore.inMemory(initial: cloudCredentials)
    let discovery = TydomGatewayDiscovery(
        dependencies: .init(
            subnetHosts: { [] },
            probeHost: { _, _, _ in false },
            probeWebSocketInfo: { _, _, _, _, _ in false }
        )
    )
    let environment = TydomConnectionResolver.Environment(
        credentialStore: credentialStore,
        gatewayMacStore: gatewayMacStore,
        cloudCredentialStore: cloudCredentialStore,
        discovery: discovery,
        remoteHost: "mediation.tydom.com",
        now: { Date() },
        makeSession: { URLSession(configuration: .ephemeral) },
        fetchSites: { _, _ in [] },
        fetchSitesPayload: { _, _ in Data() },
        fetchGatewayPassword: { _, _, _, _ in "secret" },
        probeConnection: { _ in false },
        log: { _ in }
    )
    let resolver = TydomConnectionResolver(environment: environment)
    let onDisconnect = resolver.makeOnDisconnect()

    // When
    await onDisconnect()

    // Then
    let storedMac = try await gatewayMacStore.load()
    let storedCredentials = try await credentialStore.load(gatewayId)
    let storedCloud = try await cloudCredentialStore.load()
    #expect(storedMac == nil)
    #expect(storedCredentials == nil)
    #expect(storedCloud == nil)
}
