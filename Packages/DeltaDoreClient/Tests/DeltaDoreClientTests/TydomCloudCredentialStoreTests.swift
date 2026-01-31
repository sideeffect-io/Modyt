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

@Test func resolver_onDisconnectClearsSelectedSiteAndCloudCredentials() async throws {
    // Given
    let selectedSite = TydomSelectedSite(
        id: "site-1",
        name: "Home",
        gatewayMac: "AA:BB:CC:DD:EE:FF"
    )
    let selectedSiteStore = TydomSelectedSiteStore.inMemory(initial: [
        "default": selectedSite
    ])
    let cloudCredentials = TydomConnection.CloudCredentials(
        email: "user@example.com",
        password: "secret"
    )
    let cloudCredentialStore = TydomCloudCredentialStore.inMemory(initial: cloudCredentials)
    let discovery = TydomGatewayDiscovery(
        dependencies: .init(
            discoverBonjour: { _, _ in [] },
            subnetHosts: { [] },
            probeHost: { _, _, _ in false }
        )
    )
    let environment = TydomConnectionResolver.Environment(
        credentialStore: .inMemory(),
        selectedSiteStore: selectedSiteStore,
        cloudCredentialStore: cloudCredentialStore,
        discovery: discovery,
        remoteHost: "mediation.tydom.com",
        now: { Date() },
        makeSession: { URLSession(configuration: .ephemeral) },
        probeConnection: { _ in false }
    )
    let resolver = TydomConnectionResolver(environment: environment)
    let onDisconnect = resolver.makeOnDisconnect(selectedSiteAccount: "default")

    // When
    await onDisconnect()

    // Then
    let storedSite = try await selectedSiteStore.load("default")
    let storedCredentials = try await cloudCredentialStore.load()
    #expect(storedSite == nil)
    #expect(storedCredentials == nil)
}
