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
