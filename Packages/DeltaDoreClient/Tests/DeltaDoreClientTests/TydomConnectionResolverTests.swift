import Foundation
import Testing
@testable import DeltaDoreClient

@Test func resolver_usesStoredCredentialsWithoutCloudFetch() async throws {
    // Given
    let gatewayMac = "AA:BB:CC:DD:EE:FF"
    let credentials = TydomGatewayCredentials(
        mac: gatewayMac,
        password: "secret",
        cachedLocalIP: "192.168.1.10",
        updatedAt: Date()
    )
    let normalizedMac = TydomMac.normalize(gatewayMac)
    let gatewayId = TydomMac.normalize(gatewayMac)
    let credentialStore = TydomGatewayCredentialStore.inMemory(initial: [gatewayId: credentials])
    let gatewayMacStore = TydomGatewayMacStore.inMemory(initial: gatewayMac)
    let cloudCredentialStore = TydomCloudCredentialStore.inMemory()
    let discovery = TydomGatewayDiscovery(dependencies: .init(
        subnetHosts: { [] },
        probeHost: { _, _, _ in false },
        probeWebSocketInfo: { _, _, _, _, _ in false }
    ))
    let fetchSitesCalls = CallCounter()
    let fetchSitesPayloadCalls = CallCounter()
    let fetchPasswordCalls = CallCounter()
    let environment = TydomConnectionResolver.Environment(
        credentialStore: credentialStore,
        gatewayMacStore: gatewayMacStore,
        cloudCredentialStore: cloudCredentialStore,
        discovery: discovery,
        remoteHost: "mediation.tydom.com",
        now: { Date() },
        makeSession: { URLSession(configuration: .ephemeral) },
        fetchSites: { _, _ in
            await fetchSitesCalls.increment()
            return []
        },
        fetchSitesPayload: { _, _ in
            await fetchSitesPayloadCalls.increment()
            return Data()
        },
        fetchGatewayPassword: { _, _, _, _ in
            await fetchPasswordCalls.increment()
            return "secret"
        },
        probeConnection: { _ in true },
        log: { _ in }
    )
    let resolver = TydomConnectionResolver(environment: environment)

    // When
    let resolution = try await resolver.resolve(
        .init(mode: .auto, credentialPolicy: .useStoredDataOnly)
    )

    // Then
    #expect(resolution.configuration.mac == normalizedMac)
    #expect(resolution.configuration.mode == .local(host: "192.168.1.10"))
    #expect(await fetchSitesCalls.count() == 0)
    #expect(await fetchSitesPayloadCalls.count() == 0)
    #expect(await fetchPasswordCalls.count() == 0)
}

@Test func resolver_missingGatewayCredentialsThrowsWhenStoredOnly() async {
    // Given
    let credentialStore = TydomGatewayCredentialStore.inMemory()
    let gatewayMacStore = TydomGatewayMacStore.inMemory(initial: nil)
    let cloudCredentialStore = TydomCloudCredentialStore.inMemory()
    let discovery = TydomGatewayDiscovery(dependencies: .init(
        subnetHosts: { [] },
        probeHost: { _, _, _ in false },
        probeWebSocketInfo: { _, _, _, _, _ in false }
    ))
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

    // When / Then
    do {
        _ = try await resolver.resolve(
            .init(mode: .auto, credentialPolicy: .useStoredDataOnly)
        )
        #expect(Bool(false), "Expected missingGatewayCredentials error")
    } catch {
        guard let resolverError = error as? TydomConnectionResolver.ResolverError else {
            #expect(Bool(false), "Expected ResolverError, got \\(error)")
            return
        }
        switch resolverError {
        case .missingGatewayMac:
            #expect(Bool(true))
        default:
            #expect(Bool(false), "Expected missingGatewayMac, got \\(resolverError)")
        }
    }
}

@Test func resolver_selectsSiteWithSelectorAndFetchesPassword() async throws {
    // Given
    let gatewayMacStore = TydomGatewayMacStore.inMemory(initial: nil)
    let credentialStore = TydomGatewayCredentialStore.inMemory()
    let cloudCredentialStore = TydomCloudCredentialStore.inMemory()
    let discovery = TydomGatewayDiscovery(dependencies: .init(
        subnetHosts: { [] },
        probeHost: { _, _, _ in false },
        probeWebSocketInfo: { _, _, _, _, _ in false }
    ))
    let fetchPasswordCalls = CallCounter()
    let firstMac = "AA:BB:CC:DD:EE:01"
    let secondMac = "AA:BB:CC:DD:EE:02"
    let secondNormalized = TydomMac.normalize(secondMac)
    let sites = [
        TydomCloudSitesProvider.Site(
            id: "1",
            name: "Home",
            gateways: [TydomCloudSitesProvider.Gateway(mac: firstMac, name: nil)]
        ),
        TydomCloudSitesProvider.Site(
            id: "2",
            name: "Office",
            gateways: [TydomCloudSitesProvider.Gateway(mac: secondMac, name: nil)]
        )
    ]
    let environment = TydomConnectionResolver.Environment(
        credentialStore: credentialStore,
        gatewayMacStore: gatewayMacStore,
        cloudCredentialStore: cloudCredentialStore,
        discovery: discovery,
        remoteHost: "mediation.tydom.com",
        now: { Date() },
        makeSession: { URLSession(configuration: .ephemeral) },
        fetchSites: { _, _ in sites },
        fetchSitesPayload: { _, _ in Data() },
        fetchGatewayPassword: { _, _, _, _ in
            await fetchPasswordCalls.increment()
            return "secret"
        },
        probeConnection: { _ in true },
        log: { _ in }
    )
    let resolver = TydomConnectionResolver(environment: environment)
    let credentials = TydomConnection.CloudCredentials(
        email: "user@example.com",
        password: "password"
    )

    // When
    let resolution = try await resolver.resolve(
        .init(
            mode: .auto,
            credentialPolicy: .allowCloudDataFetch,
            cloudCredentials: credentials
        ),
        selectSiteIndex: { _ in 1 }
    )

    // Then
    #expect(resolution.configuration.mac == secondNormalized)
    #expect(await fetchPasswordCalls.count() == 1)
    let storedMac = try await gatewayMacStore.load()
    #expect(storedMac == secondNormalized)
}

private actor CallCounter {
    private var value: Int = 0

    func increment() {
        value += 1
    }

    func count() -> Int {
        value
    }
}
