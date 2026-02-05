import Foundation
#if canImport(Network)
import Network
import Security
#endif

/// WebSocket connection to a Tydom gateway using HTTP Digest authentication.
///
/// Example:
/// ```swift
/// let config = TydomConnection.Configuration(
///     mode: .local(host: "192.168.1.50"),
///     mac: "AA:BB:CC:DD:EE:FF",
///     password: "gateway-password"
/// )
/// let connection = TydomConnection(configuration: config)
/// try await connection.connect()
///
/// Task {
///     for await data in await connection.messages() {
///         // Handle incoming HTTP-over-WS frames.
///     }
/// }
///
/// let request = "GET /ping HTTP/1.1\r\n\r\n"
/// try await connection.send(Data(request.utf8))
/// ```
public actor TydomConnection {
    let configuration: Configuration
    private let dependencies: Dependencies
    private let log: @Sendable (String) -> Void

    private var session: URLSession?
    private var socketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var keepAliveTask: Task<Void, Never>?
    private var webSocketDelegate: InsecureTLSDelegate?
    private var isWebSocketOpen = false
#if canImport(Network)
    private let nwQueue = DispatchQueue(label: "tydom.nw.websocket")
#endif

    private let messageStream: AsyncStream<Data>
    private var messageContinuation: AsyncStream<Data>.Continuation?
    private let activityStore = TydomAppActivityStore()

    public init(
        configuration: Configuration,
        log: @escaping @Sendable (String) -> Void = { _ in },
        onDisconnect: (@Sendable () async -> Void)? = nil
    ) {
        let dependencies = Dependencies.live(onDisconnect: onDisconnect ?? {})
        self.init(configuration: configuration, dependencies: dependencies, log: log)
    }

    init(
        configuration: Configuration,
        dependencies: Dependencies,
        log: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.configuration = configuration
        self.dependencies = dependencies
        self.log = log

        let streamResult = AsyncStream<Data>.makeStream()
        self.messageStream = streamResult.stream
        self.messageContinuation = streamResult.continuation

    }

    deinit {
        receiveTask?.cancel()
        keepAliveTask?.cancel()
        socketTask?.cancel(with: .goingAway, reason: nil)
        if let session {
            dependencies.invalidateSession(session)
        }
    }

    public func messages() -> AsyncStream<Data> {
        messageStream
    }

    public func setAppActive(_ isActive: Bool) async {
        await activityStore.setActive(isActive)
    }

    func isAppActive() async -> Bool {
        await activityStore.isAppActive()
    }

    public func connect(
        startReceiving shouldStartReceiving: Bool = true,
        requestTimeout: TimeInterval? = nil
    ) async throws {
        guard socketTask == nil else { return }
        log("Connecting to \(configuration.webSocketURL.absoluteString)")

        let passwordSession = dependencies.makeSession(
            configuration.allowInsecureTLS,
            configuration.timeout,
            nil
        )
        let password = try await resolvePassword(using: passwordSession)
        dependencies.invalidateSession(passwordSession)

        let handshakeSession = dependencies.makeSession(
            configuration.allowInsecureTLS,
            configuration.timeout,
            nil
        )
        let challenge = try await fetchDigestChallenge(
            using: handshakeSession,
            randomBytes: dependencies.randomBytes
        )
        dependencies.invalidateSession(handshakeSession)

        let adjustedChallenge = adjustDigestChallenge(challenge, isRemote: configuration.isRemote)
        let authorization = try buildDigestAuthorization(
            challenge: adjustedChallenge,
            username: configuration.digestUsername,
            password: password,
            method: "GET",
            uri: configuration.httpsURL.requestTarget,
            randomBytes: dependencies.randomBytes
        )
        log("Digest authorization prepared for \(configuration.host) uri=\(configuration.httpsURL.requestTarget)")

        let session = makeWebSocketSession(forProbe: shouldStartReceiving == false)
        self.session = session

        var request = URLRequest(url: configuration.webSocketURL)
        if let requestTimeout {
            request.timeoutInterval = requestTimeout
        } else if shouldStartReceiving {
            request.timeoutInterval = 24 * 60 * 60
        } else {
            request.timeoutInterval = configuration.timeout
        }
        request.setValue(authorization, forHTTPHeaderField: "Authorization")

        let task = session.webSocketTask(with: request)
        task.resume()

        self.socketTask = task
        log("WebSocket task resumed.")
        if shouldStartReceiving {
            startReceiving(from: task)
            startKeepAlive()
        }
    }

    public func disconnect() {
        isWebSocketOpen = false
        receiveTask?.cancel()
        receiveTask = nil
        keepAliveTask?.cancel()
        keepAliveTask = nil

        socketTask?.cancel(with: .goingAway, reason: nil)
        socketTask = nil
        if let session {
            dependencies.invalidateSession(session)
        }
        session = nil
        webSocketDelegate = nil
        log("Disconnected.")
        Task { await dependencies.onDisconnect() }
    }

    public func send(_ data: Data) async throws {
        guard let task = socketTask else {
            log("Send failed: not connected.")
            throw ConnectionError.notConnected
        }
        let payload = applyOutgoingPrefix(to: data)
        log("WebSocket send bytes=\(payload.count) preview=\(preview(payload))")
        try await task.send(.data(payload))
    }

    public func send(text: String) async throws {
        guard let task = socketTask else {
            log("Send failed: not connected.")
            throw ConnectionError.notConnected
        }
        let payload = applyOutgoingPrefix(to: Data(text.utf8))
        log("WebSocket send bytes=\(payload.count) preview=\(preview(payload))")
        try await task.send(.data(payload))
    }

    public func pingAndWaitForResponse(
        timeout: TimeInterval,
        closeAfterSuccess: Bool = false
    ) async throws -> Bool {
        guard let task = socketTask else {
            log("Ping failed: not connected.")
            throw ConnectionError.notConnected
        }
        let payload = applyOutgoingPrefix(to: Data(TydomCommand.ping().request.utf8))
        log("WebSocket ping bytes=\(payload.count) preview=\(preview(payload))")
        try await task.send(.data(payload))
        let response = try await receiveOnce(task: task, timeout: timeout)
        switch response {
        case .data(let data):
            log("WebSocket ping recv bytes=\(data.count) preview=\(preview(data))")
        case .string(let string):
            let snippet = String(string.prefix(120))
            log("WebSocket ping recv string chars=\(string.count) preview=\(snippet)")
        @unknown default:
            break
        }
        if closeAfterSuccess {
            disconnect()
        }
        return true
    }

    private func startReceiving(from task: URLSessionWebSocketTask) {
        receiveTask?.cancel()
        receiveTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    let message = try await task.receive()
                    switch message {
                    case .data(let data):
                        log("WebSocket recv data bytes=\(data.count) preview=\(preview(data))")
                        await self.handleIncoming(data)
                    case .string(let string):
                        let snippet = String(string.prefix(120))
                        log("WebSocket recv string chars=\(string.count) preview=\(snippet)")
                        await self.handleIncoming(Data(string.utf8))
                    @unknown default:
                        break
                    }
                } catch {
                    if Task.isCancelled { break }
                    let closeCode = task.closeCode.rawValue
                    let reason = task.closeReason.flatMap { String(data: $0, encoding: .utf8) } ?? "n/a"
                    log("WebSocket receive failed: \(error) (closeCode=\(closeCode), reason=\(reason))")
                    await self.handleReceiveFailure(task: task)
                    break
                }
            }
        }
    }

#if canImport(Network)
    private func startNWConnection(_ connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let gate = ConnectionGate()
            connection.stateUpdateHandler = { state in
                DeltaDoreDebugLog.log("NWConnection state=\(state)")
                switch state {
                case .ready:
                    gate.resumeOnce(continuation, result: .success(()))
                case .failed(let error):
                    gate.resumeOnce(continuation, result: .failure(error))
                case .cancelled:
                    gate.resumeOnce(continuation, result: .failure(ConnectionError.invalidResponse))
                default:
                    break
                }
            }
            connection.start(queue: nwQueue)
        }
    }

    private func fetchDigestChallengeNetwork(
        tlsOptions: NWProtocolTLS.Options,
        includeUpgradeHeaders: Bool
    ) async throws -> DigestChallenge {
        do {
            return try await fetchDigestChallengeNetwork(
                tlsOptions: tlsOptions,
                includeUpgradeHeaders: includeUpgradeHeaders,
                timeout: configuration.timeout
            )
        } catch {
            DeltaDoreDebugLog.log("Digest challenge with upgrade failed error=\(error)")
            return try await fetchDigestChallengeNetwork(
                tlsOptions: tlsOptions,
                includeUpgradeHeaders: false,
                timeout: configuration.timeout
            )
        }
    }

    private func fetchDigestChallengeNetwork(
        tlsOptions: NWProtocolTLS.Options,
        includeUpgradeHeaders: Bool,
        timeout: TimeInterval
    ) async throws -> DigestChallenge {
        let parameters = NWParameters(tls: tlsOptions)
        let connection = NWConnection(
            host: NWEndpoint.Host(configuration.host),
            port: NWEndpoint.Port(rawValue: 443)!,
            using: parameters
        )
        try await startNWConnection(connection)

        let request = buildDigestChallengeRequest(includeUpgradeHeaders: includeUpgradeHeaders)
        try await sendRaw(connection: connection, data: Data(request.utf8))

        let responseData = try await receiveHTTPHeader(connection: connection, timeout: timeout)
        connection.cancel()

        guard let responseText = String(data: responseData, encoding: .utf8) else {
            throw ConnectionError.invalidResponse
        }
        let (status, headers, headerBlock) = parseHTTPHeaders(from: responseText)
        let authenticateLines = headerBlock
            .split(separator: "\r\n")
            .filter { $0.lowercased().hasPrefix("www-authenticate:") }
            .map { String($0) }
        DeltaDoreDebugLog.log(
            "Digest challenge response host=\(configuration.host) status=\(status) includeUpgrade=\(includeUpgradeHeaders) headers=\(headers.keys.sorted())"
        )
        let rawHeader: String?
        if let digestLine = authenticateLines.first(where: { $0.lowercased().contains("digest") }) {
            rawHeader = digestLine.split(separator: ":", maxSplits: 1).dropFirst().first.map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } else {
            rawHeader = headers["www-authenticate"]
        }
        guard let rawHeader else {
            let snippet = headerBlock.prefix(400)
            DeltaDoreDebugLog.log(
                "Digest challenge missing WWW-Authenticate host=\(configuration.host) includeUpgrade=\(includeUpgradeHeaders) raw=\(snippet) authLines=\(authenticateLines)"
            )
            DeltaDoreDebugLog.log("Digest challenge missing WWW-Authenticate header includeUpgrade=\(includeUpgradeHeaders)")
            throw ConnectionError.missingChallenge
        }
        DeltaDoreDebugLog.log(
            "Digest challenge header host=\(configuration.host) value=\(rawHeader)"
        )
        let challenge = try DigestChallenge.parse(from: rawHeader)
        DeltaDoreDebugLog.log(
            "Digest challenge parsed host=\(configuration.host) realm=\(challenge.realm) qop=\(challenge.qop ?? "nil") algo=\(challenge.algorithm ?? "nil")"
        )
        return challenge
    }

    private func buildDigestChallengeRequest(includeUpgradeHeaders: Bool) -> String {
        var lines: [String] = [
            "GET \(configuration.httpsURL.requestTarget) HTTP/1.1",
            "Host: \(configuration.host):443",
            "Accept: */*"
        ]
        if includeUpgradeHeaders {
            let key = Data(dependencies.randomBytes(16)).base64EncodedString()
            lines.append("Connection: Upgrade")
            lines.append("Upgrade: websocket")
            lines.append("Sec-WebSocket-Key: \(key)")
            lines.append("Sec-WebSocket-Version: 13")
        }
        lines.append("")
        lines.append("")
        return lines.joined(separator: "\r\n")
    }

    private func sendRaw(connection: NWConnection, data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            })
        }
    }

    private func receiveHTTPHeader(connection: NWConnection, timeout: TimeInterval) async throws -> Data {
        let deadline = Date().addingTimeInterval(timeout)
        var buffer = Data()
        let delimiter = Data("\r\n\r\n".utf8)
        while Date() < deadline {
            let chunk = try await receiveRaw(connection: connection)
            if chunk.isEmpty { continue }
            buffer.append(chunk)
            if buffer.range(of: delimiter) != nil {
                return buffer
            }
        }
        throw ConnectionError.invalidResponse
    }

    private func receiveRaw(connection: NWConnection) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: data ?? Data())
                }
            }
        }
    }

    private func parseHTTPHeaders(from response: String) -> (Int, [String: String], String) {
        let parts = response.components(separatedBy: "\r\n\r\n")
        let headerBlock = parts.first ?? ""
        let lines = headerBlock.split(separator: "\r\n")
        let statusLine = lines.first ?? ""
        let status = statusLine.split(separator: " ").dropFirst().first.flatMap { Int($0) } ?? 0
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colonIndex = line.firstIndex(of: ":") else { continue }
            let name = line[..<colonIndex].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: colonIndex)...].trimmingCharacters(in: .whitespacesAndNewlines)
            headers[name] = value
        }
        return (status, headers, headerBlock)
    }

    private func makeTLSOptions(allowInsecureTLS: Bool, host: String) -> NWProtocolTLS.Options {
        let options = NWProtocolTLS.Options()
        let secOptions = options.securityProtocolOptions
        if allowInsecureTLS {
            sec_protocol_options_set_verify_block(secOptions, { _, _, completion in
                completion(true)
            }, nwQueue)
            sec_protocol_options_set_peer_authentication_required(secOptions, false)
            sec_protocol_options_set_min_tls_protocol_version(secOptions, .TLSv12)
            sec_protocol_options_set_max_tls_protocol_version(secOptions, .TLSv12)
            sec_protocol_options_set_tls_renegotiation_enabled(secOptions, true)
        }
        sec_protocol_options_set_tls_server_name(secOptions, host)
        return options
    }

    private final class ConnectionGate: @unchecked Sendable {
        private let lock = NSLock()
        private var didResume = false

        func resumeOnce(_ continuation: CheckedContinuation<Void, Error>, result: Result<Void, Error>) {
            lock.lock()
            let shouldResume = !didResume
            if shouldResume {
                didResume = true
            }
            lock.unlock()

            guard shouldResume else { return }
            switch result {
            case .success(let value):
                continuation.resume(returning: value)
            case .failure(let error):
                continuation.resume(throwing: error)
            }
        }
    }
#endif

    private func startKeepAlive() {
        keepAliveTask?.cancel()
        let config = configuration.keepAlive
        guard config.isEnabled else { return }
        keepAliveTask = Task { [weak self] in
            guard let self else { return }
            let sleepNanoseconds = UInt64(config.intervalSeconds) * 1_000_000_000
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: sleepNanoseconds)
                } catch {
                    break
                }
                if config.onlyWhenActive {
                    let isActive = await self.isAppActive()
                    guard isActive else { continue }
                }
                _ = try? await self.send(TydomCommand.ping())
            }
        }
    }

    func waitForWebSocketOpen(timeout: TimeInterval) async throws {
        if isWebSocketOpen { return }
        let deadline = Date().addingTimeInterval(timeout)
        while !isWebSocketOpen && Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        guard isWebSocketOpen else {
            log("WebSocket open timed out after \(timeout)s")
            throw ConnectionError.receiveFailed
        }
    }

    private func receiveOnce(
        task: URLSessionWebSocketTask,
        timeout: TimeInterval
    ) async throws -> URLSessionWebSocketTask.Message {
        try await withThrowingTaskGroup(of: URLSessionWebSocketTask.Message.self) { group in
            group.addTask {
                try await task.receive()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw ConnectionError.receiveFailed
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private func makeWebSocketSession(forProbe: Bool) -> URLSession {
        let sessionConfig = URLSessionConfiguration.default
        if forProbe {
            sessionConfig.timeoutIntervalForRequest = configuration.timeout
            sessionConfig.timeoutIntervalForResource = configuration.timeout
        } else {
            sessionConfig.timeoutIntervalForRequest = 24 * 60 * 60
            sessionConfig.timeoutIntervalForResource = 24 * 60 * 60
        }
        if #available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *) {
            if configuration.allowInsecureTLS {
                sessionConfig.tlsMinimumSupportedProtocolVersion = .TLSv12
                sessionConfig.tlsMaximumSupportedProtocolVersion = .TLSv12
                DeltaDoreDebugLog.log("Session TLS range set to v1.2 (allowInsecureTLS)")
            }
        }
        let delegate = InsecureTLSDelegate(
            allowInsecureTLS: configuration.allowInsecureTLS,
            credential: nil,
            onWebSocketOpen: { [weak self] _ in
                Task { await self?.markWebSocketOpen() }
            }
        )
        webSocketDelegate = delegate
        return URLSession(configuration: sessionConfig, delegate: delegate, delegateQueue: nil)
    }

    private func markWebSocketOpen() {
        isWebSocketOpen = true
    }

    private func handleReceiveFailure(task: URLSessionWebSocketTask) {
        if socketTask === task {
            socketTask = nil
        }
    }

    private func handleIncoming(_ data: Data) {
        let cleaned = stripIncomingPrefix(from: data)
        messageContinuation?.yield(cleaned)
    }

    private func resolvePassword(using session: URLSession) async throws -> String {
        if let password = configuration.password {
            return password
        }
        guard let credentials = configuration.cloudCredentials else {
            throw ConnectionError.missingCredentials
        }
        return try await dependencies.fetchGatewayPassword(credentials, configuration.mac, session)
    }

    private func fetchDigestChallenge(
        using session: URLSession,
        randomBytes: @Sendable (Int) -> [UInt8]
    ) async throws -> DigestChallenge {
        do {
            return try await fetchDigestChallenge(
                using: session,
                randomBytes: randomBytes,
                includeUpgradeHeaders: true
            )
        } catch {
            DeltaDoreDebugLog.log("Digest challenge with upgrade failed error=\(error)")
            return try await fetchDigestChallenge(
                using: session,
                randomBytes: randomBytes,
                includeUpgradeHeaders: false
            )
        }
    }

    private func fetchDigestChallenge(
        using session: URLSession,
        randomBytes: @Sendable (Int) -> [UInt8],
        includeUpgradeHeaders: Bool
    ) async throws -> DigestChallenge {
        var request = URLRequest(url: configuration.httpsURL)
        request.httpMethod = "GET"
        request.timeoutInterval = configuration.timeout
        let handshakeHeaders = buildHandshakeHeaders(
            randomBytes: randomBytes,
            includeUpgradeHeaders: includeUpgradeHeaders
        )
        for (key, value) in handshakeHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConnectionError.invalidResponse
        }
        let status = httpResponse.statusCode
        DeltaDoreDebugLog.log(
            "Digest challenge response status=\(status) includeUpgrade=\(includeUpgradeHeaders)"
        )
        let rawHeader = httpResponse.allHeaderFields.first { key, _ in
            String(describing: key).lowercased() == "www-authenticate"
        }?.value as? String
        guard let rawHeader else {
            DeltaDoreDebugLog.log(
                "Digest challenge missing WWW-Authenticate header includeUpgrade=\(includeUpgradeHeaders)"
            )
            throw ConnectionError.missingChallenge
        }
        return try DigestChallenge.parse(from: rawHeader)
    }

    private func buildHandshakeHeaders(
        randomBytes: @Sendable (Int) -> [UInt8],
        includeUpgradeHeaders: Bool
    ) -> [String: String] {
        var headers: [String: String] = [
            "Host": "\(configuration.host):443",
            "Accept": "*/*"
        ]
        guard includeUpgradeHeaders else { return headers }
        let key = Data(randomBytes(16)).base64EncodedString()
        headers["Connection"] = "Upgrade"
        headers["Upgrade"] = "websocket"
        headers["Sec-WebSocket-Key"] = key
        headers["Sec-WebSocket-Version"] = "13"
        return headers
    }

    private func shouldRetryDigestChallenge(error: Error) -> Bool {
        if let urlError = error as? URLError {
            return urlError.code == .networkConnectionLost
        }
        return false
    }

    private func applyOutgoingPrefix(to data: Data) -> Data {
        guard let prefix = configuration.commandPrefix else { return data }
        var output = Data([prefix])
        output.append(data)
        return output
    }

    private func stripIncomingPrefix(from data: Data) -> Data {
        guard let prefix = configuration.commandPrefix else { return data }
        guard data.first == prefix else { return data }
        return Data(data.dropFirst())
    }


    nonisolated private func preview(_ data: Data, limit: Int = 120) -> String {
        let prefix = data.prefix(limit)
        let snippet = String(data: prefix, encoding: .isoLatin1)
            ?? String(decoding: prefix, as: UTF8.self)
        return snippet.replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    private func buildDigestAuthorization(
        challenge: DigestChallenge,
        username: String,
        password: String,
        method: String,
        uri: String,
        randomBytes: @Sendable (Int) -> [UInt8]
    ) throws -> String {
        try DigestAuthorizationBuilder.build(
            challenge: challenge,
            username: username,
            password: password,
            method: method,
            uri: uri,
            randomBytes: randomBytes
        )
    }

    private func adjustDigestChallenge(_ challenge: DigestChallenge, isRemote: Bool) -> DigestChallenge {
        let realm = isRemote ? "ServiceMedia" : "protected area"
        return DigestChallenge(
            realm: realm,
            nonce: challenge.nonce,
            qop: challenge.qop ?? "auth",
            opaque: challenge.opaque,
            algorithm: challenge.algorithm
        )
    }
}

private extension URL {
    var requestTarget: String {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return path
        }
        components.scheme = nil
        components.host = nil
        components.port = nil
        return components.string ?? path
    }
}
