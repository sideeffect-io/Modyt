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
        connect: { configuration, onDisconnect in
            TydomConnection(configuration: configuration, onDisconnect: onDisconnect)
        },
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
        connect: { _, _ in nil },
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
        connect: { configuration, onDisconnect in
            TydomConnection(configuration: configuration, onDisconnect: onDisconnect)
        },
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

@Test func resolver_forceLocalDoesNotFallbackToRemote() async {
    // Given
    let gatewayMac = "AA:BB:CC:DD:EE:FF"
    let credentials = TydomGatewayCredentials(
        mac: gatewayMac,
        password: "secret",
        cachedLocalIP: nil,
        updatedAt: Date()
    )
    let gatewayId = TydomMac.normalize(gatewayMac)
    let credentialStore = TydomGatewayCredentialStore.inMemory(initial: [gatewayId: credentials])
    let gatewayMacStore = TydomGatewayMacStore.inMemory(initial: gatewayMac)
    let cloudCredentialStore = TydomCloudCredentialStore.inMemory()
    let remoteConnectAttempts = CallCounter()
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
        connect: { configuration, onDisconnect in
            if case .remote = configuration.mode {
                await remoteConnectAttempts.increment()
            }
            return TydomConnection(configuration: configuration, onDisconnect: onDisconnect)
        },
        log: { _ in }
    )
    let resolver = TydomConnectionResolver(environment: environment)

    // When / Then
    do {
        _ = try await resolver.resolve(
            .init(mode: .local, credentialPolicy: .useStoredDataOnly)
        )
        #expect(Bool(false), "Expected local-only resolution to fail")
    } catch {
        #expect(await remoteConnectAttempts.count() == 0)
    }
}

@Test func resolver_forceLocalRefreshesCachedIPFromFreshDiscovery() async throws {
    // Given
    let gatewayMac = "AA:BB:CC:DD:EE:FF"
    let staleHost = "192.168.1.10"
    let refreshedHost = "192.168.1.20"
    let credentials = TydomGatewayCredentials(
        mac: gatewayMac,
        password: "secret",
        cachedLocalIP: staleHost,
        updatedAt: Date()
    )
    let gatewayId = TydomMac.normalize(gatewayMac)
    let credentialStore = TydomGatewayCredentialStore.inMemory(initial: [gatewayId: credentials])
    let gatewayMacStore = TydomGatewayMacStore.inMemory(initial: gatewayMac)
    let cloudCredentialStore = TydomCloudCredentialStore.inMemory()
    let probedHosts = ProbeHostRecorder()
    let discovery = TydomGatewayDiscovery(dependencies: .init(
        subnetHosts: { [refreshedHost] },
        probeHost: { host, _, _ in
            host == refreshedHost
        },
        probeWebSocketInfo: { host, _, _, _, _ in
            await probedHosts.record(host)
            return host == refreshedHost
        },
        log: { _ in }
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
        connect: { configuration, onDisconnect in
            TydomConnection(configuration: configuration, onDisconnect: onDisconnect)
        },
        log: { _ in }
    )
    let resolver = TydomConnectionResolver(environment: environment)

    // When
    let resolution = try await resolver.resolve(
        .init(mode: .local, credentialPolicy: .useStoredDataOnly)
    )

    // Then
    #expect(resolution.configuration.mode == .local(host: refreshedHost))
    #expect(resolution.credentials.cachedLocalIP == refreshedHost)
    let storedCredentials = try await credentialStore.load(gatewayId)
    #expect(storedCredentials?.cachedLocalIP == refreshedHost)
    #expect(await probedHosts.values() == [staleHost, refreshedHost])
}

@Test func resolver_autoCanRefreshCachedIPFromFreshDiscovery() async throws {
    // Given
    let gatewayMac = "AA:BB:CC:DD:EE:FF"
    let staleHost = "192.168.1.10"
    let refreshedHost = "192.168.1.20"
    let credentials = TydomGatewayCredentials(
        mac: gatewayMac,
        password: "secret",
        cachedLocalIP: staleHost,
        updatedAt: Date()
    )
    let gatewayId = TydomMac.normalize(gatewayMac)
    let credentialStore = TydomGatewayCredentialStore.inMemory(initial: [gatewayId: credentials])
    let gatewayMacStore = TydomGatewayMacStore.inMemory(initial: gatewayMac)
    let cloudCredentialStore = TydomCloudCredentialStore.inMemory()
    let probedHosts = ProbeHostRecorder()
    let connectAttempts = ConnectAttemptRecorder()
    let discovery = TydomGatewayDiscovery(dependencies: .init(
        subnetHosts: { [refreshedHost] },
        probeHost: { host, _, _ in
            host == staleHost || host == refreshedHost
        },
        probeWebSocketInfo: { host, _, _, _, _ in
            await probedHosts.record(host)
            return host == refreshedHost
        },
        log: { _ in }
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
        connect: { configuration, onDisconnect in
            await connectAttempts.record(mode: configuration.mode, timeout: configuration.timeout)
            return TydomConnection(configuration: configuration, onDisconnect: onDisconnect)
        },
        log: { _ in }
    )
    let resolver = TydomConnectionResolver(environment: environment)

    // When
    let resolution = try await resolver.resolve(
        .init(
            mode: .auto,
            credentialPolicy: .useStoredDataOnly,
            preferFreshLocalDiscovery: true
        )
    )

    // Then
    #expect(resolution.configuration.mode == .local(host: refreshedHost))
    #expect(resolution.credentials.cachedLocalIP == refreshedHost)
    let storedCredentials = try await credentialStore.load(gatewayId)
    #expect(storedCredentials?.cachedLocalIP == refreshedHost)
    #expect(await probedHosts.values() == [staleHost, refreshedHost])
    #expect(await connectAttempts.values() == ["local:192.168.1.20@10.0"])
}

@Test func resolver_autoUsesConfiguredLocalAndRemoteTimeouts() async throws {
    // Given
    let gatewayMac = "AA:BB:CC:DD:EE:FF"
    let credentials = TydomGatewayCredentials(
        mac: gatewayMac,
        password: "secret",
        cachedLocalIP: "192.168.1.10",
        updatedAt: Date()
    )
    let gatewayId = TydomMac.normalize(gatewayMac)
    let credentialStore = TydomGatewayCredentialStore.inMemory(initial: [gatewayId: credentials])
    let gatewayMacStore = TydomGatewayMacStore.inMemory(initial: gatewayMac)
    let cloudCredentialStore = TydomCloudCredentialStore.inMemory()
    let attempts = ConnectAttemptRecorder()
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
        connect: { configuration, onDisconnect in
            await attempts.record(mode: configuration.mode, timeout: configuration.timeout)
            switch configuration.mode {
            case .local:
                return nil
            case .remote:
                return TydomConnection(configuration: configuration, onDisconnect: onDisconnect)
            }
        },
        log: { _ in }
    )
    let resolver = TydomConnectionResolver(environment: environment)
    let timings = TydomConnectionResolver.Options.Timings(
        discoveryTimeout: 1.0,
        probeTimeout: 0.2,
        infoTimeout: 0.5,
        localConnectTimeout: 1.25,
        remoteConnectTimeout: 4.5
    )

    // When
    let resolution = try await resolver.resolve(
        .init(
            mode: .auto,
            credentialPolicy: .useStoredDataOnly,
            timings: timings
        )
    )

    // Then
    #expect(resolution.configuration.mode == .remote(host: "mediation.tydom.com"))
    #expect(await attempts.values() == [
        "local:192.168.1.10@1.25",
        "remote:mediation.tydom.com@4.5"
    ])
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

private actor ConnectAttemptRecorder {
    private var recorded: [String] = []

    func record(mode: TydomConnection.Configuration.Mode, timeout: TimeInterval) {
        switch mode {
        case .local(let host):
            recorded.append("local:\(host)@\(timeout)")
        case .remote(let host):
            recorded.append("remote:\(host)@\(timeout)")
        }
    }

    func values() -> [String] {
        recorded
    }
}

private actor ProbeHostRecorder {
    private var recorded: [String] = []

    func record(_ host: String) {
        recorded.append(host)
    }

    func values() -> [String] {
        recorded
    }
}
