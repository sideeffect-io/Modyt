import Foundation

public struct DeltaDoreClient: Sendable {
    public enum ConnectionFlowStatus: Sendable {
        case connectWithStoredCredentials
        case connectWithNewCredentials
    }

    public struct StoredCredentialsFlowOptions: Sendable {
        public enum Mode: Sendable { case auto, forceLocal, forceRemote }
        public let mode: Mode

        public init(mode: Mode = .auto) {
            self.mode = mode
        }
    }

    public struct NewCredentialsFlowOptions: Sendable {
        public enum Mode: Sendable {
            case auto(cloudCredentials: TydomConnection.CloudCredentials)
            case forceLocal(cloudCredentials: TydomConnection.CloudCredentials, localIP: String, localMAC: String)
            case forceRemote(cloudCredentials: TydomConnection.CloudCredentials)
        }

        public let mode: Mode

        public init(mode: Mode) {
            self.mode = mode
        }
    }

    public typealias SiteIndexSelector = @Sendable (_ sites: [TydomCloudSitesProvider.Site]) async -> Int?
    public typealias Site = TydomCloudSitesProvider.Site

    public struct ConnectionSession: Sendable {
        public let connection: TydomConnection
    }

    public struct Dependencies: Sendable {
        public var inspectFlow: @Sendable () async -> ConnectionFlowStatus
        public var connectStored: @Sendable (StoredCredentialsFlowOptions) async throws -> ConnectionSession
        public var connectNew: @Sendable (NewCredentialsFlowOptions, SiteIndexSelector?) async throws -> ConnectionSession
        public var listSites: @Sendable (TydomConnection.CloudCredentials) async throws -> [Site]
        public var listSitesPayload: @Sendable (TydomConnection.CloudCredentials) async throws -> Data
        public var clearStoredData: @Sendable () async -> Void

        public init(
            inspectFlow: @escaping @Sendable () async -> ConnectionFlowStatus,
            connectStored: @escaping @Sendable (StoredCredentialsFlowOptions) async throws -> ConnectionSession,
            connectNew: @escaping @Sendable (NewCredentialsFlowOptions, SiteIndexSelector?) async throws -> ConnectionSession,
            listSites: @escaping @Sendable (TydomConnection.CloudCredentials) async throws -> [Site],
            listSitesPayload: @escaping @Sendable (TydomConnection.CloudCredentials) async throws -> Data,
            clearStoredData: @escaping @Sendable () async -> Void
        ) {
            self.inspectFlow = inspectFlow
            self.connectStored = connectStored
            self.connectNew = connectNew
            self.listSites = listSites
            self.listSitesPayload = listSitesPayload
            self.clearStoredData = clearStoredData
        }

        public static func live(
            credentialService: String = "io.sideeffect.deltadoreclient.gateway",
            gatewayMacService: String = "io.sideeffect.deltadoreclient.gateway-mac",
            cloudCredentialService: String = "io.sideeffect.deltadoreclient.cloud-credentials",
            remoteHost: String = "mediation.tydom.com",
            now: @escaping @Sendable () -> Date = { Date() }
        ) -> Dependencies {
            let environment = TydomConnectionResolver.Environment.live(
                credentialService: credentialService,
                gatewayMacService: gatewayMacService,
                cloudCredentialService: cloudCredentialService,
                remoteHost: remoteHost,
                now: now
            )
            let resolver = TydomConnectionResolver(environment: environment)

            let buildSession: @Sendable (TydomConnectionResolver.Resolution) async throws -> ConnectionSession = { resolution in
                let connection = TydomConnection(
                    configuration: resolution.configuration,
                    onDisconnect: resolution.onDisconnect
                )
                try await connection.connect()
                return ConnectionSession(connection: connection)
            }

            return Dependencies(
                inspectFlow: {
                    guard let mac = try? await environment.gatewayMacStore.load() else {
                        return .connectWithNewCredentials
                    }
                    let gatewayId = TydomMac.normalize(mac)
                    if let _ = try? await environment.credentialStore.load(gatewayId) {
                        return .connectWithStoredCredentials
                    }
                    return .connectWithNewCredentials
                },
                connectStored: { options in
                    let resolverOptions = TydomConnectionResolver.Options(
                        mode: mapStoredMode(options.mode),
                        credentialPolicy: .useStoredDataOnly
                    )
                    let resolution = try await resolver.resolve(resolverOptions)
                    return try await buildSession(resolution)
                },
                connectNew: { options, selectSiteIndex in
                    let (mode, cloudCredentials, localHostOverride, macOverride) = mapNewMode(options.mode)
                    let resolverOptions = TydomConnectionResolver.Options(
                        mode: mode,
                        credentialPolicy: .allowCloudDataFetch,
                        localHostOverride: localHostOverride,
                        macOverride: macOverride,
                        cloudCredentials: cloudCredentials
                    )
                    let resolution = try await resolver.resolve(
                        resolverOptions,
                        selectSiteIndex: selectSiteIndex
                    )
                    return try await buildSession(resolution)
                },
                listSites: { credentials in
                    try await resolver.listSites(cloudCredentials: credentials)
                },
                listSitesPayload: { credentials in
                    try await resolver.listSitesPayload(cloudCredentials: credentials)
                },
                clearStoredData: {
                    await resolver.clearPersistedData()
                }
            )
        }
    }

    private let dependencies: Dependencies

    public init(dependencies: Dependencies = .live()) {
        self.dependencies = dependencies
    }

    public static func live(
        credentialService: String = "io.sideeffect.deltadoreclient.gateway",
        gatewayMacService: String = "io.sideeffect.deltadoreclient.gateway-mac",
        cloudCredentialService: String = "io.sideeffect.deltadoreclient.cloud-credentials",
        remoteHost: String = "mediation.tydom.com",
        now: @escaping @Sendable () -> Date = { Date() }
    ) -> DeltaDoreClient {
        DeltaDoreClient(
            dependencies: .live(
                credentialService: credentialService,
                gatewayMacService: gatewayMacService,
                cloudCredentialService: cloudCredentialService,
                remoteHost: remoteHost,
                now: now
            )
        )
    }

    public func inspectConnectionFlow() async -> ConnectionFlowStatus {
        await dependencies.inspectFlow()
    }

    public func connectWithStoredCredentials(
        options: StoredCredentialsFlowOptions
    ) async throws -> ConnectionSession {
        try await dependencies.connectStored(options)
    }

    public func connectWithNewCredentials(
        options: NewCredentialsFlowOptions,
        selectSiteIndex: SiteIndexSelector? = nil
    ) async throws -> ConnectionSession {
        try await dependencies.connectNew(options, selectSiteIndex)
    }

    public func listSites(
        cloudCredentials: TydomConnection.CloudCredentials
    ) async throws -> [Site] {
        try await dependencies.listSites(cloudCredentials)
    }

    public func listSitesPayload(
        cloudCredentials: TydomConnection.CloudCredentials
    ) async throws -> Data {
        try await dependencies.listSitesPayload(cloudCredentials)
    }

    public func clearStoredData() async {
        await dependencies.clearStoredData()
    }
}

private func mapStoredMode(
    _ mode: DeltaDoreClient.StoredCredentialsFlowOptions.Mode
) -> TydomConnectionResolver.Options.Mode {
    switch mode {
    case .auto:
        return .auto
    case .forceLocal:
        return .local
    case .forceRemote:
        return .remote
    }
}

private func mapNewMode(
    _ mode: DeltaDoreClient.NewCredentialsFlowOptions.Mode
) -> (
    mode: TydomConnectionResolver.Options.Mode,
    cloudCredentials: TydomConnection.CloudCredentials,
    localHostOverride: String?,
    macOverride: String?
) {
    switch mode {
    case .auto(let cloudCredentials):
        return (.auto, cloudCredentials, nil, nil)
    case .forceLocal(let cloudCredentials, let localIP, let localMAC):
        return (.local, cloudCredentials, localIP, localMAC)
    case .forceRemote(let cloudCredentials):
        return (.remote, cloudCredentials, nil, nil)
    }
}
