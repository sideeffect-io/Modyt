import Foundation
import Testing
@testable import DeltaDoreClient

@Test func gatewayDiscovery_includesCachedIPFirst() async {
    // Given
    let dependencies = TydomGatewayDiscovery.Dependencies(
        subnetHosts: { [] },
        probeHost: { _, _, _ in false },
        probeWebSocketInfo: { _, _, _, _, _ in false }
    )
    let discovery = TydomGatewayDiscovery(dependencies: dependencies)
    let config = TydomGatewayDiscoveryConfig()
    let credentials = TydomGatewayCredentials(
        mac: "AA:BB:CC:DD:EE:FF",
        password: "test",
        cachedLocalIP: "192.168.1.20",
        updatedAt: Date()
    )

    // When
    let candidates = await discovery.discover(
        credentials: credentials,
        cachedIP: "192.168.1.20",
        config: config
    )

    // Then
    #expect(candidates.first?.host == "192.168.1.20")
    #expect(candidates.first?.method == .cachedIP)
}

@Test func gatewayDiscovery_strictValidationReturnsNoCandidatesWhenInfoProbeFails() async {
    // Given
    let dependencies = TydomGatewayDiscovery.Dependencies(
        subnetHosts: { ["192.168.1.20"] },
        probeHost: { _, _, _ in true },
        probeWebSocketInfo: { _, _, _, _, _ in false }
    )
    let discovery = TydomGatewayDiscovery(dependencies: dependencies)
    let config = TydomGatewayDiscoveryConfig(
        validateWithInfo: true,
        allowUnvalidatedFallback: false
    )
    let credentials = TydomGatewayCredentials(
        mac: "AA:BB:CC:DD:EE:FF",
        password: "test",
        cachedLocalIP: "192.168.1.20",
        updatedAt: Date()
    )

    // When
    let candidates = await discovery.discover(
        credentials: credentials,
        cachedIP: "192.168.1.20",
        config: config
    )

    // Then
    #expect(candidates.isEmpty)
}

@Test func gatewayDiscovery_excludesFailedCachedHostFromFallbackDiscovery() async {
    // Given
    let validatedHosts = HostRecorder()
    let dependencies = TydomGatewayDiscovery.Dependencies(
        subnetHosts: { ["192.168.1.20", "192.168.1.30"] },
        probeHost: { _, _, _ in true },
        probeWebSocketInfo: { host, _, _, _, _ in
            await validatedHosts.record(host)
            return host == "192.168.1.30"
        }
    )
    let discovery = TydomGatewayDiscovery(dependencies: dependencies)
    let config = TydomGatewayDiscoveryConfig(
        discoveryTimeout: 0.5,
        probeTimeout: 0.1,
        infoTimeout: 0.1,
        validateWithInfo: true,
        allowUnvalidatedFallback: false
    )
    let credentials = TydomGatewayCredentials(
        mac: "AA:BB:CC:DD:EE:FF",
        password: "test",
        cachedLocalIP: "192.168.1.20",
        updatedAt: Date()
    )

    // When
    let candidates = await discovery.discover(
        credentials: credentials,
        cachedIP: "192.168.1.20",
        excludingHosts: ["192.168.1.20"],
        config: config
    )

    // Then
    #expect(candidates.map(\.host) == ["192.168.1.30"])
    #expect(await validatedHosts.values() == ["192.168.1.30"])
}

@Test func gatewayDiscovery_discoveryTimeoutCapsProbeBudget() async {
    // Given
    let probeTimeouts = TimeoutRecorder()
    let dependencies = TydomGatewayDiscovery.Dependencies(
        subnetHosts: { ["192.168.1.20", "192.168.1.21", "192.168.1.22"] },
        probeHost: { _, _, timeout in
            await probeTimeouts.record(timeout)
            let sleepTime = UInt64(timeout * 1_000_000_000)
            try? await Task.sleep(nanoseconds: sleepTime)
            return false
        },
        probeWebSocketInfo: { _, _, _, _, _ in false }
    )
    let discovery = TydomGatewayDiscovery(dependencies: dependencies)
    let config = TydomGatewayDiscoveryConfig(
        discoveryTimeout: 0.05,
        probeTimeout: 0.5,
        probeConcurrency: 1,
        validateWithInfo: false
    )
    let credentials = TydomGatewayCredentials(
        mac: "AA:BB:CC:DD:EE:FF",
        password: "test",
        cachedLocalIP: nil,
        updatedAt: Date()
    )
    let clock = ContinuousClock()
    let start = clock.now

    // When
    let candidates = await discovery.discover(
        credentials: credentials,
        cachedIP: nil,
        config: config
    )
    let elapsed = clock.now - start

    // Then
    #expect(candidates.isEmpty)
    let recordedTimeouts = await probeTimeouts.values()
    #expect(recordedTimeouts.isEmpty == false)
    #expect(recordedTimeouts.allSatisfy { $0 <= 0.06 })
    #expect(durationSeconds(elapsed) < 0.15)
}

private actor HostRecorder {
    private var recorded: [String] = []

    func record(_ host: String) {
        recorded.append(host)
    }

    func values() -> [String] {
        recorded
    }
}

private actor TimeoutRecorder {
    private var recorded: [TimeInterval] = []

    func record(_ timeout: TimeInterval) {
        recorded.append(timeout)
    }

    func values() -> [TimeInterval] {
        recorded
    }
}

private func durationSeconds(_ duration: Duration) -> TimeInterval {
    let components = duration.components
    return TimeInterval(components.seconds) +
        (TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000)
}
