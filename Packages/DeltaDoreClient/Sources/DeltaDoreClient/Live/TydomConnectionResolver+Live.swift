import Foundation

extension TydomConnectionResolver.Environment {
    static func live(
        credentialService: String = "io.sideeffect.deltadoreclient.gateway",
        gatewayMacService: String = "io.sideeffect.deltadoreclient.gateway-mac",
        cloudCredentialService: String = "io.sideeffect.deltadoreclient.cloud-credentials",
        remoteHost: String = "mediation.tydom.com",
        now: @escaping @Sendable () -> Date = { Date() },
        log: @escaping @Sendable (String) -> Void = { DeltaDoreDebugLog.log($0) }
    ) -> TydomConnectionResolver.Environment {
        TydomConnectionResolver.Environment(
            credentialStore: .liveKeychain(service: credentialService, now: now),
            gatewayMacStore: .liveKeychain(service: gatewayMacService),
            cloudCredentialStore: .liveKeychain(service: cloudCredentialService),
            discovery: TydomGatewayDiscovery(dependencies: .live(log: log)),
            remoteHost: remoteHost,
            now: now,
            makeSession: { URLSession(configuration: .default) },
            fetchSites: { credentials, session in
                try await TydomCloudSitesProvider.fetchSites(
                    email: credentials.email,
                    password: credentials.password,
                    session: session
                )
            },
            fetchSitesPayload: { credentials, session in
                try await TydomCloudSitesProvider.fetchSitesPayload(
                    email: credentials.email,
                    password: credentials.password,
                    session: session
                )
            },
            fetchGatewayPassword: { email, password, mac, session in
                try await TydomCloudPasswordProvider.fetchGatewayPassword(
                    email: email,
                    password: password,
                    mac: mac,
                    session: session
                )
            },
            probeConnection: { configuration in
                log(
                    "Probe connection start host=\(configuration.host) mode=\(configuration.mode) mac=\(TydomMac.normalize(configuration.mac)) timeout=\(configuration.timeout)s"
                )
                let connection = TydomConnection(
                    configuration: configuration,
                    log: log
                )
                do {
                    try await connection.connect(startReceiving: false)
                    let verified = await verifyGateway(
                        connection: connection,
                        timeout: configuration.timeout,
                        log: log
                    )
                    if verified == false {
                        await connection.disconnect()
                    }
                    log(
                        "Probe connection result host=\(configuration.host) verified=\(verified)"
                    )
                    return verified
                } catch {
                    await connection.disconnect()
                    log(
                        "Probe connection error host=\(configuration.host) error=\(error)"
                    )
                    return false
                }
            },
            log: log
        )
    }
}

private func verifyGateway(
    connection: TydomConnection,
    timeout: TimeInterval,
    log: @escaping @Sendable (String) -> Void
) async -> Bool {
    do {
        return try await connection.pingAndWaitForResponse(
            timeout: timeout,
            closeAfterSuccess: true
        )
    } catch {
        log("Verify gateway ping failed error=\(error)")
        return false
    }
}
