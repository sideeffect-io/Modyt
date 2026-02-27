import Foundation
import Testing
@testable import MoDyt

struct ClimateFixtureTests {
    @Test
    func boilerFixtureContainsUsableThermostatSignal() throws {
        let fixture = try loadFixture()
        let devices = fixture.boilerMultiEndpoint.map(makeDevice)

        let usableDescriptors = devices.compactMap { $0.thermostatDescriptor() }

        #expect(usableDescriptors.isEmpty == false)
        #expect(usableDescriptors.contains { $0.temperature?.value == 20.5 })
    }

    @Test
    func shHvacFixtureRoutesToHeatPumpAndExtractsTemperature() throws {
        let fixture = try loadFixture()
        let device = makeDevice(from: fixture.shHvacSample)

        #expect(device.controlKind == .heatPump)
        #expect(device.climateCurrentTemperatureSignal()?.value == 19.9)
        #expect(device.climateSetpointSignal()?.value == 20.5)
    }

    private func makeDevice(from sample: ClimateSample) -> Device {
        Device(
            id: "1_42",
            endpointId: 1,
            name: sample.name,
            usage: sample.usage,
            kind: "kind",
            data: sample.data,
            metadata: sample.metadata,
            isFavorite: false,
            dashboardOrder: nil,
            updatedAt: Date()
        )
    }

    private func loadFixture() throws -> ClimateFixture {
        let baseURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
        let fixtureURL = baseURL
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("tydom_climate_samples.json")

        let data = try Data(contentsOf: fixtureURL)
        return try JSONDecoder().decode(ClimateFixture.self, from: data)
    }
}

private struct ClimateFixture: Decodable {
    let boilerMultiEndpoint: [ClimateSample]
    let shHvacSample: ClimateSample
}

private struct ClimateSample: Decodable {
    let usage: String
    let name: String
    let data: [String: JSONValue]
    let metadata: [String: JSONValue]?
}
