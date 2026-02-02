import Foundation

extension TydomConnection.Dependencies {
    static func live(onDisconnect: @escaping @Sendable () async -> Void = {}) -> TydomConnection.Dependencies {
        TydomConnection.Dependencies(
            makeSession: { allowInsecureTLS, timeout, credential in
                let configuration = URLSessionConfiguration.default
                configuration.timeoutIntervalForRequest = timeout
                configuration.timeoutIntervalForResource = timeout
                if #available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *) {
                    if allowInsecureTLS {
                        configuration.tlsMinimumSupportedProtocolVersion = .TLSv12
                        configuration.tlsMaximumSupportedProtocolVersion = .TLSv12
                        DeltaDoreDebugLog.log("Session TLS range set to v1.2 (allowInsecureTLS)")
                    }
                }
                let delegate = InsecureTLSDelegate(
                    allowInsecureTLS: allowInsecureTLS,
                    credential: credential
                )
                return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
            },
            randomBytes: { count in
                (0..<count).map { _ in UInt8.random(in: UInt8.min...UInt8.max) }
            },
            now: { Date() },
            fetchGatewayPassword: { credentials, mac, session in
                try await TydomCloudPasswordProvider.fetchGatewayPassword(
                    email: credentials.email,
                    password: credentials.password,
                    mac: mac,
                    session: session
                )
            },
            invalidateSession: { session in
                session.invalidateAndCancel()
            },
            onDisconnect: onDisconnect
        )
    }
}
