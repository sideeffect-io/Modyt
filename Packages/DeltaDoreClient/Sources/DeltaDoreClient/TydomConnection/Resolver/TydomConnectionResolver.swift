import Foundation

struct TydomConnectionResolver: Sendable {
    typealias SiteIndexSelector = @Sendable (_ sites: [TydomCloudSitesProvider.Site]) async -> Int?

    struct Environment: Sendable {
        var credentialStore: TydomGatewayCredentialStore
        var gatewayMacStore: TydomGatewayMacStore
        var cloudCredentialStore: TydomCloudCredentialStore
        var discovery: TydomGatewayDiscovery
        var remoteHost: String
        var now: @Sendable () -> Date
        var makeSession: @Sendable () -> URLSession
        var probeConnection: @Sendable (_ configuration: TydomConnection.Configuration) async -> Bool

        init(
            credentialStore: TydomGatewayCredentialStore,
            gatewayMacStore: TydomGatewayMacStore,
            cloudCredentialStore: TydomCloudCredentialStore,
            discovery: TydomGatewayDiscovery,
            remoteHost: String,
            now: @escaping @Sendable () -> Date,
            makeSession: @escaping @Sendable () -> URLSession,
            probeConnection: @escaping @Sendable (_ configuration: TydomConnection.Configuration) async -> Bool
        ) {
            self.credentialStore = credentialStore
            self.gatewayMacStore = gatewayMacStore
            self.cloudCredentialStore = cloudCredentialStore
            self.discovery = discovery
            self.remoteHost = remoteHost
            self.now = now
            self.makeSession = makeSession
            self.probeConnection = probeConnection
        }

        static func live(
            credentialService: String = "io.sideeffect.deltadoreclient.gateway",
            gatewayMacService: String = "io.sideeffect.deltadoreclient.gateway-mac",
            cloudCredentialService: String = "io.sideeffect.deltadoreclient.cloud-credentials",
            remoteHost: String = "mediation.tydom.com",
            now: @escaping @Sendable () -> Date = { Date() }
        ) -> Environment {
            Environment(
                credentialStore: .liveKeychain(service: credentialService, now: now),
                gatewayMacStore: .liveKeychain(service: gatewayMacService),
                cloudCredentialStore: .liveKeychain(service: cloudCredentialService),
                discovery: TydomGatewayDiscovery(dependencies: .live()),
                remoteHost: remoteHost,
                now: now,
                makeSession: { URLSession(configuration: .default) },
                probeConnection: { configuration in
                    DeltaDoreDebugLog.log(
                        "Probe connection start host=\(configuration.host) mode=\(configuration.mode) mac=\(TydomMac.normalize(configuration.mac)) timeout=\(configuration.timeout)s"
                    )
                    let connection = TydomConnection(
                        configuration: configuration,
                        log: { message in
                            DeltaDoreDebugLog.log(message)
                        }
                    )
                    do {
                        try await connection.connect(startReceiving: false)
                        let verified = await verifyGateway(
                            connection: connection,
                            timeout: configuration.timeout
                        )
                        if verified == false {
                            await connection.disconnect()
                        }
                        DeltaDoreDebugLog.log(
                            "Probe connection result host=\(configuration.host) verified=\(verified)"
                        )
                        return verified
                    } catch {
                        await connection.disconnect()
                        DeltaDoreDebugLog.log(
                            "Probe connection error host=\(configuration.host) error=\(error)"
                        )
                        return false
                    }
                }
            )
        }
    }

    struct Options: Sendable {
        enum Mode: Sendable {
            case auto
            case local
            case remote
        }

        enum CredentialPolicy: Sendable {
            case useStoredDataOnly
            case allowCloudDataFetch
        }

        let mode: Mode
        let credentialPolicy: CredentialPolicy
        let localHostOverride: String?
        let macOverride: String?
        let cloudCredentials: TydomConnection.CloudCredentials?
        let siteIndex: Int?
        let allowInsecureTLS: Bool?
        let timeout: TimeInterval
        let polling: TydomConnection.Configuration.Polling
        let onDecision: (@Sendable (TydomConnectionState.Decision) async -> Void)?

        init(
            mode: Mode,
            credentialPolicy: CredentialPolicy,
            localHostOverride: String? = nil,
            macOverride: String? = nil,
            cloudCredentials: TydomConnection.CloudCredentials? = nil,
            siteIndex: Int? = nil,
            allowInsecureTLS: Bool? = nil,
            timeout: TimeInterval = 10.0,
            polling: TydomConnection.Configuration.Polling = .init(),
            onDecision: (@Sendable (TydomConnectionState.Decision) async -> Void)? = nil
        ) {
            self.mode = mode
            self.credentialPolicy = credentialPolicy
            self.localHostOverride = localHostOverride
            self.macOverride = macOverride
            self.cloudCredentials = cloudCredentials
            self.siteIndex = siteIndex
            self.allowInsecureTLS = allowInsecureTLS
            self.timeout = timeout
            self.polling = polling
            self.onDecision = onDecision
        }
    }

    struct Resolution: Sendable {
        let configuration: TydomConnection.Configuration
        let credentials: TydomGatewayCredentials
        let decision: TydomConnectionState.Decision?
        let onDisconnect: (@Sendable () async -> Void)?
    }

    enum ResolverError: Error, Sendable {
        case missingCloudCredentials
        case missingSiteSelection
        case invalidSiteIndex(Int, siteCount: Int)
        case missingGateway(String)
        case noSites
        case missingGatewayCredentials
        case missingGatewayMac
        case invalidConfiguration
        case remoteFailed
    }

    private let environment: Environment

    init(environment: Environment = .live()) {
        self.environment = environment
    }

    func listSites(
        cloudCredentials: TydomConnection.CloudCredentials
    ) async throws -> [TydomCloudSitesProvider.Site] {
        try? await environment.cloudCredentialStore.save(cloudCredentials)
        let session = environment.makeSession()
        defer { session.invalidateAndCancel() }
        return try await TydomCloudSitesProvider.fetchSites(
            email: cloudCredentials.email,
            password: cloudCredentials.password,
            session: session
        )
    }

    func listSitesPayload(
        cloudCredentials: TydomConnection.CloudCredentials
    ) async throws -> Data {
        try? await environment.cloudCredentialStore.save(cloudCredentials)
        let session = environment.makeSession()
        defer { session.invalidateAndCancel() }
        return try await TydomCloudSitesProvider.fetchSitesPayload(
            email: cloudCredentials.email,
            password: cloudCredentials.password,
            session: session
        )
    }

    func makeOnDisconnect() -> @Sendable () async -> Void {
        { [self] in
            await clearPersistedData()
        }
    }

    func clearPersistedData() async {
        if let mac = try? await environment.gatewayMacStore.load() {
            let gatewayId = TydomMac.normalize(mac)
            try? await environment.credentialStore.delete(gatewayId)
        }
        try? await environment.gatewayMacStore.delete()
        try? await environment.cloudCredentialStore.deleteAll()
    }

    func resolve(
        _ options: Options,
        selectSiteIndex: SiteIndexSelector? = nil
    ) async throws -> Resolution {
        if let cloudCredentials = options.cloudCredentials {
            try? await environment.cloudCredentialStore.save(cloudCredentials)
        }

        let credentials = try await resolveGatewayCredentials(
            options: options,
            selectSiteIndex: selectSiteIndex
        )

        let cache = CredentialsCache(initial: credentials)
        let dependencies = makeOrchestratorDependencies(
            options: options,
            cache: cache
        )
        var state = TydomConnectionState(
            override: overrideMode(for: options.mode)
        )
        let orchestrator = TydomConnectionOrchestrator(dependencies: dependencies)
        await orchestrator.handle(event: .start, state: &state)

        let cachedCredentials = await cache.get()
        guard let decision = state.lastDecision,
              let latestCredentials = state.credentials ?? cachedCredentials else {
            throw ResolverError.invalidConfiguration
        }

        if state.phase == .failed {
            if decision.reason == .remoteFailed {
                await clearPersistedData()
                throw ResolverError.remoteFailed
            }
            throw ResolverError.invalidConfiguration
        }

        guard let configuration = buildConfiguration(
            decision: decision,
            credentials: latestCredentials,
            options: options
        ) else {
            throw ResolverError.invalidConfiguration
        }

        let onDisconnect = makeOnDisconnect()
        return Resolution(
            configuration: configuration,
            credentials: latestCredentials,
            decision: decision,
            onDisconnect: onDisconnect
        )
    }

    private func overrideMode(for mode: Options.Mode) -> TydomConnectionState.ModeOverride {
        switch mode {
        case .auto:
            return .none
        case .local:
            return .forceLocal
        case .remote:
            return .forceRemote
        }
    }

    private func resolveGatewayCredentials(
        options: Options,
        selectSiteIndex: SiteIndexSelector?
    ) async throws -> TydomGatewayCredentials {
        let selectedMac = try await resolveSelectedMac(
            options: options,
            selectSiteIndex: selectSiteIndex
        )
        DeltaDoreDebugLog.log(
            "Resolve credentials selectedMac=\(TydomMac.normalize(selectedMac)) mode=\(options.mode)"
        )

        let gatewayId = TydomMac.normalize(selectedMac)
        if let stored = try? await environment.credentialStore.load(gatewayId) {
            return stored
        }

        guard options.credentialPolicy == .allowCloudDataFetch else {
            throw ResolverError.missingGatewayCredentials
        }

        let cloudCredentials: TydomConnection.CloudCredentials
        if let provided = options.cloudCredentials {
            cloudCredentials = provided
        } else if let stored = await loadStoredCloudCredentials() {
            cloudCredentials = stored
        } else {
            throw ResolverError.missingGatewayCredentials
        }

        let fetcher = TydomGatewayCredentialFetcher(
            dependencies: .init(
                makeSession: environment.makeSession,
                fetchPassword: { email, password, mac, session in
                    try await TydomCloudPasswordProvider.fetchGatewayPassword(
                        email: email,
                        password: password,
                        mac: mac,
                        session: session
                    )
                },
                now: environment.now,
                save: { gatewayId, credentials in
                    try await environment.credentialStore.save(gatewayId, credentials)
                }
            )
        )
        let credentials = try await fetcher.fetchAndPersist(
            gatewayId: gatewayId,
            gatewayMac: selectedMac,
            cloudCredentials: cloudCredentials
        )
        return credentials
    }

    private func resolveSelectedMac(
        options: Options,
        selectSiteIndex: SiteIndexSelector?
    ) async throws -> String {
        if let macOverride = options.macOverride, macOverride.isEmpty == false {
            try? await environment.gatewayMacStore.save(macOverride)
            return macOverride
        }

        if options.credentialPolicy == .useStoredDataOnly {
            if let storedMac = try? await environment.gatewayMacStore.load() {
                return storedMac
            }
            throw ResolverError.missingGatewayMac
        }

        let cloudCredentials: TydomConnection.CloudCredentials
        if let provided = options.cloudCredentials {
            cloudCredentials = provided
        } else if let stored = await loadStoredCloudCredentials() {
            cloudCredentials = stored
        } else {
            throw ResolverError.missingCloudCredentials
        }

        let sites = try await listSites(cloudCredentials: cloudCredentials)
        guard sites.isEmpty == false else {
            throw ResolverError.noSites
        }

        let chosenIndex: Int?
        if sites.count == 1 {
            chosenIndex = 0
        } else if let providedIndex = options.siteIndex {
            chosenIndex = providedIndex
        } else if let selectSiteIndex {
            chosenIndex = await selectSiteIndex(sites)
        } else {
            chosenIndex = nil
        }

        guard let chosenIndex else {
            throw ResolverError.missingSiteSelection
        }

        let selectedMac = try selectMac(from: sites, index: chosenIndex)
        try? await environment.gatewayMacStore.save(selectedMac)
        DeltaDoreDebugLog.log("Resolve site selected index=\(chosenIndex) mac=\(selectedMac)")
        return selectedMac
    }

    private func loadStoredCloudCredentials() async -> TydomConnection.CloudCredentials? {
        try? await environment.cloudCredentialStore.load()
    }

    private func selectMac(
        from sites: [TydomCloudSitesProvider.Site],
        index: Int
    ) throws -> String {
        guard sites.indices.contains(index) else {
            throw ResolverError.invalidSiteIndex(index, siteCount: sites.count)
        }
        let site = sites[index]
        guard let gateway = site.gateways.first else {
            throw ResolverError.missingGateway(site.name)
        }
        return gateway.mac
    }

    private func makeOrchestratorDependencies(
        options: Options,
        cache: CredentialsCache
    ) -> TydomConnectionOrchestrator.Dependencies {
        let discovery = environment.discovery
        let allowInsecureTLS = options.allowInsecureTLS
        let timeout = options.timeout
        let localHostOverride = options.localHostOverride
        let remoteHost = environment.remoteHost

        let connect: @Sendable (String, TydomGatewayCredentials?, TydomConnection.Configuration.Mode) async -> Bool = { host, credentials, mode in
            guard let credentials else { return false }
            let config = TydomConnection.Configuration(
                mode: mode,
                mac: credentials.mac,
                password: credentials.password,
                cloudCredentials: nil,
                allowInsecureTLS: allowInsecureTLS,
                timeout: timeout,
                polling: TydomConnection.Configuration.Polling(intervalSeconds: 0, onlyWhenActive: false)
            )
            return await self.environment.probeConnection(config)
        }

        return TydomConnectionOrchestrator.Dependencies(
            loadCredentials: {
                await cache.get()
            },
            saveCredentials: { credentials in
                let gatewayId = TydomMac.normalize(credentials.mac)
                try? await self.environment.credentialStore.save(gatewayId, credentials)
                try? await self.environment.gatewayMacStore.save(credentials.mac)
                await cache.set(credentials)
            },
            discoverLocal: {
                guard let credentials = await cache.get() else { return [] }
                DeltaDoreDebugLog.log(
                    "Discovery request mac=\(credentials.mac) cachedIP=\(credentials.cachedLocalIP ?? "nil")"
                )
                let config = TydomGatewayDiscoveryConfig(
                    discoveryTimeout: min(timeout, 10),
                    probeTimeout: min(timeout, 0.6),
                    probeConcurrency: 256,
                    probePorts: [443],
                    bonjourServiceTypes: [],
                    infoTimeout: min(timeout, 10),
                    infoConcurrency: 32,
                    allowInsecureTLS: allowInsecureTLS ?? true,
                    validateWithInfo: true
                )
                let candidates = await discovery.discover(
                    credentials: credentials,
                    cachedIP: credentials.cachedLocalIP,
                    config: config
                )
                return candidates
            },
            connectLocal: { host in
                let credentials = await cache.get()
                if let overrideHost = localHostOverride, overrideHost.isEmpty == false {
                    return await connect(overrideHost, credentials, .local(host: overrideHost))
                }
                return await connect(host, credentials, .local(host: host))
            },
            connectRemote: {
                let credentials = await cache.get()
                return await connect(remoteHost, credentials, .remote(host: remoteHost))
            },
            emitDecision: { decision in
                if let onDecision = options.onDecision {
                    await onDecision(decision)
                }
            }
        )
    }

    private func buildConfiguration(
        decision: TydomConnectionState.Decision,
        credentials: TydomGatewayCredentials,
        options: Options
    ) -> TydomConnection.Configuration? {
        switch decision.mode {
        case .local(let host):
            let resolvedHost = (options.localHostOverride?.isEmpty == false)
                ? options.localHostOverride!
                : host
            return TydomConnection.Configuration(
                mode: .local(host: resolvedHost),
                mac: credentials.mac,
                password: credentials.password,
                cloudCredentials: nil,
                allowInsecureTLS: options.allowInsecureTLS,
                timeout: options.timeout,
                polling: options.polling
            )
        case .remote(let host):
            let resolvedHost = environment.remoteHost.isEmpty == false ? environment.remoteHost : host
            return TydomConnection.Configuration(
                mode: .remote(host: resolvedHost),
                mac: credentials.mac,
                password: credentials.password,
                cloudCredentials: nil,
                allowInsecureTLS: options.allowInsecureTLS,
                timeout: options.timeout,
                polling: options.polling
            )
        }
    }
}

extension TydomConnectionResolver.ResolverError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .missingCloudCredentials:
            return "Missing cloud credentials."
        case .missingSiteSelection:
            return "No site selection provided."
        case .invalidSiteIndex(let index, let count):
            return "Invalid site index \(index). Available range: 0...\(max(0, count - 1))."
        case .missingGateway(let name):
            return "Selected site has no gateways: \(name)."
        case .noSites:
            return "No sites returned from cloud."
        case .missingGatewayCredentials:
            return "Missing gateway credentials."
        case .missingGatewayMac:
            return "Missing gateway MAC."
        case .invalidConfiguration:
            return "Unable to build a valid connection configuration."
        case .remoteFailed:
            return "Remote connection failed."
        }
    }
}

private func verifyGateway(
    connection: TydomConnection,
    timeout: TimeInterval
) async -> Bool {
    do {
        return try await connection.pingAndWaitForResponse(
            timeout: timeout,
            closeAfterSuccess: true
        )
    } catch {
        DeltaDoreDebugLog.log("Verify gateway ping failed error=\(error)")
        return false
    }
}

private actor CredentialsCache {
    private var cached: TydomGatewayCredentials?

    init(initial: TydomGatewayCredentials?) {
        self.cached = initial
    }

    func get() -> TydomGatewayCredentials? { cached }
    func set(_ value: TydomGatewayCredentials?) { cached = value }
}
