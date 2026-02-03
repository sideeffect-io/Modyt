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
        var fetchSites: @Sendable (_ credentials: TydomConnection.CloudCredentials, _ session: URLSession) async throws -> [TydomCloudSitesProvider.Site]
        var fetchSitesPayload: @Sendable (_ credentials: TydomConnection.CloudCredentials, _ session: URLSession) async throws -> Data
        var fetchGatewayPassword: @Sendable (_ email: String, _ password: String, _ mac: String, _ session: URLSession) async throws -> String
        var connect: @Sendable (_ configuration: TydomConnection.Configuration, _ onDisconnect: @escaping @Sendable () async -> Void) async -> TydomConnection?
        var log: @Sendable (String) -> Void

        init(
            credentialStore: TydomGatewayCredentialStore,
            gatewayMacStore: TydomGatewayMacStore,
            cloudCredentialStore: TydomCloudCredentialStore,
            discovery: TydomGatewayDiscovery,
            remoteHost: String,
            now: @escaping @Sendable () -> Date,
            makeSession: @escaping @Sendable () -> URLSession,
            fetchSites: @escaping @Sendable (_ credentials: TydomConnection.CloudCredentials, _ session: URLSession) async throws -> [TydomCloudSitesProvider.Site],
            fetchSitesPayload: @escaping @Sendable (_ credentials: TydomConnection.CloudCredentials, _ session: URLSession) async throws -> Data,
            fetchGatewayPassword: @escaping @Sendable (_ email: String, _ password: String, _ mac: String, _ session: URLSession) async throws -> String,
            connect: @escaping @Sendable (_ configuration: TydomConnection.Configuration, _ onDisconnect: @escaping @Sendable () async -> Void) async -> TydomConnection?,
            log: @escaping @Sendable (String) -> Void
        ) {
            self.credentialStore = credentialStore
            self.gatewayMacStore = gatewayMacStore
            self.cloudCredentialStore = cloudCredentialStore
            self.discovery = discovery
            self.remoteHost = remoteHost
            self.now = now
            self.makeSession = makeSession
            self.fetchSites = fetchSites
            self.fetchSitesPayload = fetchSitesPayload
            self.fetchGatewayPassword = fetchGatewayPassword
            self.connect = connect
            self.log = log
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
        let connection: TydomConnection?
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
        return try await environment.fetchSites(cloudCredentials, session)
    }

    func listSitesPayload(
        cloudCredentials: TydomConnection.CloudCredentials
    ) async throws -> Data {
        try? await environment.cloudCredentialStore.save(cloudCredentials)
        let session = environment.makeSession()
        defer { session.invalidateAndCancel() }
        return try await environment.fetchSitesPayload(cloudCredentials, session)
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
        let onDisconnect = makeOnDisconnect()
        let dependencies = makeOrchestratorDependencies(
            options: options,
            cache: cache,
            onDisconnect: onDisconnect
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

        return Resolution(
            configuration: configuration,
            credentials: latestCredentials,
            decision: decision,
            onDisconnect: onDisconnect,
            connection: state.connectedConnection
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
        environment.log(
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
                    try await environment.fetchGatewayPassword(email, password, mac, session)
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
        environment.log("Resolve site selected index=\(chosenIndex) mac=\(selectedMac)")
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
        cache: CredentialsCache,
        onDisconnect: @escaping @Sendable () async -> Void
    ) -> TydomConnectionOrchestrator.Dependencies {
        let discovery = environment.discovery
        let allowInsecureTLS = options.allowInsecureTLS
        let timeout = options.timeout
        let localHostOverride = options.localHostOverride
        let remoteHost = environment.remoteHost

        let connect: @Sendable (String, TydomGatewayCredentials?, TydomConnection.Configuration.Mode) async -> TydomConnection? = { host, credentials, mode in
            guard let credentials else { return nil }
            let disconnectGate = ConnectionDisconnectGate()
            let config = TydomConnection.Configuration(
                mode: mode,
                mac: credentials.mac,
                password: credentials.password,
                cloudCredentials: nil,
                allowInsecureTLS: allowInsecureTLS,
                timeout: timeout,
                polling: options.polling
            )
            let connection = await self.environment.connect(
                config,
                {
                    if await disconnectGate.shouldClearPersistedData() {
                        await onDisconnect()
                    }
                }
            )
            if connection != nil {
                await disconnectGate.markConnected()
            }
            return connection
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
                self.environment.log(
                    "Discovery request mac=\(credentials.mac) cachedIP=\(credentials.cachedLocalIP ?? "nil")"
                )
                let config = TydomGatewayDiscoveryConfig(
                    discoveryTimeout: min(timeout, 10),
                    probeTimeout: min(timeout, 0.6),
                    probeConcurrency: 256,
                    probePorts: [443],
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

private actor CredentialsCache {
    private var cached: TydomGatewayCredentials?

    init(initial: TydomGatewayCredentials?) {
        self.cached = initial
    }

    func get() -> TydomGatewayCredentials? { cached }
    func set(_ value: TydomGatewayCredentials?) { cached = value }
}

private actor ConnectionDisconnectGate {
    private var connected = false

    func markConnected() {
        connected = true
    }

    func shouldClearPersistedData() -> Bool {
        connected
    }
}
