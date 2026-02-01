import Foundation

#if canImport(Network)
import Network
import Security

public extension TydomGatewayDiscovery.Dependencies {
    static func live() -> TydomGatewayDiscovery.Dependencies {
        TydomGatewayDiscovery.Dependencies(
            discoverBonjour: { serviceTypes, timeout in
                guard serviceTypes.isEmpty == false else { return [] }
                return await BonjourDiscovery.discover(serviceTypes: serviceTypes, timeout: timeout)
            },
            subnetHosts: {
                NetworkProbe.subnetHosts()
            },
            probeHost: { host, port, timeout in
                await NetworkProbe.tcpProbe(host: host, port: port, timeout: timeout)
            },
            probeWebSocketInfo: { host, mac, password, allowInsecureTLS, timeout in
                await WebSocketProbe.probeInfo(
                    host: host,
                    mac: mac,
                    password: password,
                    allowInsecureTLS: allowInsecureTLS,
                    timeout: timeout
                )
            }
        )
    }
}

private enum BonjourDiscovery {
    static func discover(serviceTypes: [String], timeout: TimeInterval) async -> [String] {
        await withTaskGroup(of: [String].self) { group in
            for serviceType in serviceTypes {
                group.addTask {
                    await browse(serviceType: serviceType, timeout: timeout)
                }
            }
            var hosts: [String] = []
            for await result in group {
                hosts.append(contentsOf: result)
            }
            return Array(Set(hosts))
        }
    }

    private static func browse(serviceType: String, timeout: TimeInterval) async -> [String] {
        await withCheckedContinuation { continuation in
            let browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: .init())
            let hosts = LockedHosts()
            let gate = ContinuationGate()
            let queue = DispatchQueue(label: "tydom.bonjour.browser")

            browser.browseResultsChangedHandler = { results, _ in
                for result in results {
                    switch result.endpoint {
                    case .hostPort(let host, _):
                        hosts.append(host.debugDescription)
                    default:
                        continue
                    }
                }
            }

            browser.stateUpdateHandler = { state in
                if case .failed = state {
                    browser.cancel()
                    gate.resumeOnce(continuation, value: [])
                }
            }

            browser.start(queue: queue)

            queue.asyncAfter(deadline: .now() + timeout) {
                browser.cancel()
                gate.resumeOnce(continuation, value: hosts.snapshot())
            }
        }
    }
}

private enum NetworkProbe {
    static func tcpProbe(host: String, port: Int, timeout: TimeInterval) async -> Bool {
        await withCheckedContinuation { continuation in
            guard port > 0, port <= 65535, let portValue = UInt16(exactly: port) else {
                continuation.resume(returning: false)
                return
            }
            let endpoint = NWEndpoint.Host(host)
            let parameters = NWParameters.tcp
            let gate = ContinuationGate()
            guard let nwPort = NWEndpoint.Port(rawValue: portValue) else {
                continuation.resume(returning: false)
                return
            }
            let connection = NWConnection(host: endpoint, port: nwPort, using: parameters)
            let queue = DispatchQueue(label: "tydom.tcp.probe")

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.cancel()
                    gate.resumeOnce(continuation, value: true)
                case .failed:
                    connection.cancel()
                    gate.resumeOnce(continuation, value: false)
                default:
                    break
                }
            }

            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) {
                connection.cancel()
                gate.resumeOnce(continuation, value: false)
            }
        }
    }

    static func subnetHosts() -> [String] {
        if let network = IPv4Network.inferLocal() {
            return network.hosts
        }
        return []
    }

    private static func ipv4String(_ value: UInt32) -> String {
        let a = (value >> 24) & 0xFF
        let b = (value >> 16) & 0xFF
        let c = (value >> 8) & 0xFF
        let d = value & 0xFF
        return "\(a).\(b).\(c).\(d)"
    }

}

private enum WebSocketProbe {
    static func probeInfo(
        host: String,
        mac: String,
        password: String,
        allowInsecureTLS: Bool,
        timeout: TimeInterval
    ) async -> Bool {
        let normalizedMac = TydomMac.normalize(mac)
        let path = "/mediation/client?mac=\(normalizedMac)&appli=1"
        guard let httpsURL = URL(string: "https://\(host):443\(path)"),
              let wsURL = URL(string: "wss://\(host):443\(path)") else {
            return false
        }

        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.timeoutIntervalForRequest = timeout
        sessionConfig.timeoutIntervalForResource = timeout
        let delegate = InsecureTLSDelegate(allowInsecureTLS: allowInsecureTLS, credential: nil)
        let session = URLSession(configuration: sessionConfig, delegate: delegate, delegateQueue: nil)

        do {
            let challenge = try await fetchDigestChallenge(session: session, url: httpsURL, host: host, timeout: timeout)
            let authorization = try DigestAuthorizationBuilder.build(
                challenge: challenge,
                username: normalizedMac,
                password: password,
                method: "GET",
                uri: path,
                randomBytes: { count in
                    (0..<count).map { _ in UInt8.random(in: UInt8.min...UInt8.max) }
                }
            )

            var request = URLRequest(url: wsURL)
            request.timeoutInterval = timeout
            request.setValue(authorization, forHTTPHeaderField: "Authorization")

            let task = session.webSocketTask(with: request)
            task.resume()

            defer {
                task.cancel(with: .goingAway, reason: nil)
                session.finishTasksAndInvalidate()
            }

            let pingRequest = Data(TydomCommand.ping().request.utf8)
            try await withTimeout(timeout) {
                try await task.send(.data(pingRequest))
            }

            _ = try await withTimeout(timeout) {
                try await task.receive()
            }
            return true
        } catch {
            return false
        }
    }

    private static func fetchDigestChallenge(
        session: URLSession,
        url: URL,
        host: String,
        timeout: TimeInterval
    ) async throws -> DigestChallenge {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue("Upgrade", forHTTPHeaderField: "Connection")
        request.setValue("websocket", forHTTPHeaderField: "Upgrade")
        request.setValue("\(host):443", forHTTPHeaderField: "Host")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue(WebSocketKeyGenerator.generate(), forHTTPHeaderField: "Sec-WebSocket-Key")
        request.setValue("13", forHTTPHeaderField: "Sec-WebSocket-Version")

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TydomConnection.ConnectionError.invalidResponse
        }
        guard let rawHeader = http.value(forHTTPHeaderField: "WWW-Authenticate") else {
            throw TydomConnection.ConnectionError.missingChallenge
        }
        return try DigestChallenge.parse(from: rawHeader)
    }

    // Intentionally no response parsing; any reply is enough to validate connectivity.
}

private enum WebSocketKeyGenerator {
    static func generate() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
    }
}

private func withTimeout<T: Sendable>(
    _ seconds: TimeInterval,
    operation: @Sendable @escaping () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TydomConnection.ConnectionError.receiveFailed
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

private struct IPv4Network {
    let network: UInt32
    let netmask: UInt32

    static func inferLocal() -> IPv4Network? {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let first = addrs else { return nil }
        defer { freeifaddrs(addrs) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }
            let flags = current.pointee.ifa_flags
            if (flags & UInt32(IFF_LOOPBACK)) != 0 { continue }
            guard let addr = current.pointee.ifa_addr else { continue }
            guard addr.pointee.sa_family == sa_family_t(AF_INET) else { continue }
            guard let netmask = current.pointee.ifa_netmask else { continue }

            let sockaddr = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
            let maskaddr = netmask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
            let ip = UInt32(bigEndian: sockaddr.sin_addr.s_addr)
            let mask = UInt32(bigEndian: maskaddr.sin_addr.s_addr)

            if (ip & 0xFFFF0000) == 0xA9FE0000 { continue }

            let network = ip & mask
            return IPv4Network(network: network, netmask: mask)
        }
        return nil
    }

    var hosts: [String] {
        let broadcast = network | ~netmask
        if broadcast <= network {
            return []
        }
        if broadcast - network <= 1 {
            return [IPv4Network.formatIPv4(network)]
        }

        var result: [String] = []
        var ip = network + 1
        while ip < broadcast {
            result.append(IPv4Network.formatIPv4(ip))
            ip += 1
        }
        return result
    }

    private static func formatIPv4(_ value: UInt32) -> String {
        let a = (value >> 24) & 0xff
        let b = (value >> 16) & 0xff
        let c = (value >> 8) & 0xff
        let d = value & 0xff
        return "\(a).\(b).\(c).\(d)"
    }
}

private final class ContinuationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false

    func resumeOnce<T: Sendable>(_ continuation: CheckedContinuation<T, Never>, value: T) {
        lock.lock()
        let shouldResume = !didResume
        if shouldResume {
            didResume = true
        }
        lock.unlock()

        if shouldResume {
            continuation.resume(returning: value)
        }
    }
}

private final class LockedHosts: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []

    func append(_ host: String) {
        lock.lock()
        values.append(host)
        lock.unlock()
    }

    func snapshot() -> [String] {
        lock.lock()
        let snapshot = Array(Set(values))
        lock.unlock()
        return snapshot
    }
}
#endif
