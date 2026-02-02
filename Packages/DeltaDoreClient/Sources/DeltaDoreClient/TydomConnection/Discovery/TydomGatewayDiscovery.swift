import Foundation

public struct TydomLocalGateway: Sendable, Equatable {
    public enum Method: String, Sendable, Equatable {
        case cachedIP
        case subnetProbe
    }

    public let mac: String
    public let host: String
    public let method: Method
}

public struct TydomGatewayDiscoveryConfig: Sendable, Equatable {
    public let discoveryTimeout: TimeInterval
    public let probeTimeout: TimeInterval
    public let probeConcurrency: Int
    public let probePorts: [Int]
    public let infoTimeout: TimeInterval
    public let infoConcurrency: Int
    public let allowInsecureTLS: Bool
    public let validateWithInfo: Bool

    public init(
        discoveryTimeout: TimeInterval = 4,
        probeTimeout: TimeInterval = 1.5,
        probeConcurrency: Int = 12,
        probePorts: [Int] = [443],
        infoTimeout: TimeInterval = 6,
        infoConcurrency: Int = 16,
        allowInsecureTLS: Bool = true,
        validateWithInfo: Bool = true
    ) {
        self.discoveryTimeout = discoveryTimeout
        self.probeTimeout = probeTimeout
        self.probeConcurrency = probeConcurrency
        self.probePorts = probePorts
        self.infoTimeout = infoTimeout
        self.infoConcurrency = infoConcurrency
        self.allowInsecureTLS = allowInsecureTLS
        self.validateWithInfo = validateWithInfo
    }
}

public struct TydomGatewayDiscovery: Sendable {
    public struct Dependencies: Sendable {
        public let subnetHosts: @Sendable () -> [String]
        public let probeHost: @Sendable (_ host: String, _ port: Int, _ timeout: TimeInterval) async -> Bool
        public let probeWebSocketInfo: @Sendable (
            _ host: String,
            _ mac: String,
            _ password: String,
            _ allowInsecureTLS: Bool,
            _ timeout: TimeInterval
        ) async -> Bool
        public let log: @Sendable (String) -> Void

        public init(
            subnetHosts: @escaping @Sendable () -> [String],
            probeHost: @escaping @Sendable (_ host: String, _ port: Int, _ timeout: TimeInterval) async -> Bool,
            probeWebSocketInfo: @escaping @Sendable (
                _ host: String,
                _ mac: String,
                _ password: String,
                _ allowInsecureTLS: Bool,
                _ timeout: TimeInterval
            ) async -> Bool,
            log: @escaping @Sendable (String) -> Void = { _ in }
        ) {
            self.subnetHosts = subnetHosts
            self.probeHost = probeHost
            self.probeWebSocketInfo = probeWebSocketInfo
            self.log = log
        }
    }

    public let dependencies: Dependencies

    public init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    public func discover(
        credentials: TydomGatewayCredentials,
        cachedIP: String?,
        config: TydomGatewayDiscoveryConfig
    ) async -> [TydomLocalGateway] {
        let normalizedMac = TydomMac.normalize(credentials.mac)
        dependencies.log(
            "Discovery start mac=\(normalizedMac) cachedIP=\(cachedIP ?? "nil") timeout=\(config.discoveryTimeout)s probeTimeout=\(config.probeTimeout)s ports=\(config.probePorts)"
        )
        var candidates: [TydomLocalGateway] = []

        if let cachedIP, cachedIP.isEmpty == false {
            candidates.append(
                TydomLocalGateway(mac: normalizedMac, host: cachedIP, method: .cachedIP)
            )
            if config.validateWithInfo,
               await probeInfo(host: cachedIP, credentials: credentials, config: config) {
                dependencies.log("Discovery cached candidate validated via /info host=\(cachedIP)")
                return candidates
            }
        }
        if cachedIP?.isEmpty == false {
            dependencies.log("Discovery cached candidate host=\(cachedIP ?? "")")
        }

        let subnetHosts = dependencies.subnetHosts()
        dependencies.log("Discovery subnet candidates count=\(subnetHosts.count)")
        let probeHosts = await scanOpenPort(
            subnetHosts,
            ports: config.probePorts,
            timeout: config.probeTimeout,
            maxConcurrent: max(config.probeConcurrency, 1)
        )
        if probeHosts.isEmpty {
            dependencies.log("Discovery subnet probe found 0 responsive hosts")
        } else {
            dependencies.log("Discovery subnet probe responsive hosts=\(probeHosts)")
        }
        candidates.append(contentsOf: probeHosts.map {
            TydomLocalGateway(mac: normalizedMac, host: $0, method: .subnetProbe)
        })

        let unique = uniqueCandidates(candidates)
        dependencies.log("Discovery unique candidates=\(unique.map { "\($0.host)(\($0.method.rawValue))" })")
        if config.validateWithInfo {
            let validated = await validateCandidates(unique, credentials: credentials, config: config)
            if validated.isEmpty == false {
                dependencies.log("Discovery websocket validation ok hosts=\(validated.map { $0.host })")
                return validated
            }
            dependencies.log("Discovery websocket validation found 0 hosts (falling back to unvalidated candidates)")
        }
        dependencies.log("Discovery returning candidates (no websocket verification step)")
        return unique
    }

    private func uniqueCandidates(_ candidates: [TydomLocalGateway]) -> [TydomLocalGateway] {
        var seen: Set<String> = []
        var result: [TydomLocalGateway] = []
        for candidate in candidates {
            let key = "\(candidate.host)-\(candidate.method.rawValue)"
            if seen.insert(key).inserted {
                result.append(candidate)
            }
        }
        return result
    }

    private func probeInfo(
        host: String,
        credentials: TydomGatewayCredentials,
        config: TydomGatewayDiscoveryConfig
    ) async -> Bool {
        await dependencies.probeWebSocketInfo(
            host,
            credentials.mac,
            credentials.password,
            config.allowInsecureTLS,
            config.infoTimeout
        )
    }

    private func validateCandidates(
        _ candidates: [TydomLocalGateway],
        credentials: TydomGatewayCredentials,
        config: TydomGatewayDiscoveryConfig
    ) async -> [TydomLocalGateway] {
        guard candidates.isEmpty == false else { return [] }
        let concurrency = max(config.infoConcurrency, 1)
        var iterator = candidates.makeIterator()
        return await withTaskGroup(of: TydomLocalGateway?.self) { group in
            let initial = min(concurrency, candidates.count)
            for _ in 0..<initial {
                if let candidate = iterator.next() {
                    group.addTask {
                        let ok = await probeInfo(host: candidate.host, credentials: credentials, config: config)
                        return ok ? candidate : nil
                    }
                }
            }

            while let result = await group.next() {
                if let winner = result {
                    group.cancelAll()
                    return [winner]
                }
                if let candidate = iterator.next() {
                    group.addTask {
                        let ok = await probeInfo(host: candidate.host, credentials: credentials, config: config)
                        return ok ? candidate : nil
                    }
                }
            }

            return []
        }
    }

    private func scanOpenPort(
        _ hosts: [String],
        ports: [Int],
        timeout: TimeInterval,
        maxConcurrent: Int
    ) async -> [String] {
        guard hosts.isEmpty == false, ports.isEmpty == false else { return [] }
        let portsToScan = ports
        var results: [String] = []
        var iterator = hosts.makeIterator()

        await withTaskGroup(of: String?.self) { group in
            let initial = min(maxConcurrent, hosts.count)
            for _ in 0..<initial {
                if let host = iterator.next() {
                    group.addTask {
                        for port in portsToScan {
                            let open = await dependencies.probeHost(host, port, timeout)
                            if open {
                                return host
                            }
                        }
                        return nil
                    }
                }
            }

            while let result = await group.next() {
                if let host = result {
                    results.append(host)
                }
                if let host = iterator.next() {
                    group.addTask {
                        for port in portsToScan {
                            let open = await dependencies.probeHost(host, port, timeout)
                            if open {
                                return host
                            }
                        }
                        return nil
                    }
                }
            }
        }

        return Array(Set(results)).sorted()
    }

}

actor AsyncSemaphore {
    private var value: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(value: Int) {
        self.value = value
    }

    func acquire() async {
        if value > 0 {
            value -= 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if waiters.isEmpty == false {
            let continuation = waiters.removeFirst()
            continuation.resume()
        } else {
            value += 1
        }
    }
}
