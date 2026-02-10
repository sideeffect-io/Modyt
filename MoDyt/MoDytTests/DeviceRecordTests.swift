import Foundation
import Testing
import DeltaDoreClient
@testable import MoDyt

struct DeviceRecordTests {
    @Test
    func drivingLightControlDescriptorUsesPowerAndLevelKeys() {
        let device = TestSupport.makeDevice(
            uniqueId: "light-1",
            name: "Driveway",
            usage: "light",
            data: ["on": .bool(true), "level": .number(50)],
            metadata: ["level": .object(["min": .number(0), "max": .number(200)])]
        )

        let descriptor = device.drivingLightControlDescriptor()

        #expect(descriptor?.powerKey == "on")
        #expect(descriptor?.levelKey == "level")
        #expect(descriptor?.isOn == true)
        #expect(descriptor?.level == 50)
        #expect(descriptor?.percentage == 25)
    }

    @Test
    func drivingLightControlDescriptorFallsBackToStateWhenLevelIsMissing() {
        let device = TestSupport.makeDevice(
            uniqueId: "light-2",
            name: "Garage",
            usage: "light",
            data: ["state": .bool(false)]
        )

        let descriptor = device.drivingLightControlDescriptor()

        #expect(descriptor?.powerKey == "state")
        #expect(descriptor?.levelKey == nil)
        #expect(descriptor?.isOn == false)
        #expect(descriptor?.level == 0)
        #expect(descriptor?.percentage == 0)
    }

    @Test
    func drivingLightControlDescriptorFallsBackToLevelWhenPowerIsMissing() {
        let device = TestSupport.makeDevice(
            uniqueId: "light-3",
            name: "Porch",
            usage: "light",
            data: ["level": .number(35)],
            metadata: ["level": .object(["min": .number(0), "max": .number(70)])]
        )

        let descriptor = device.drivingLightControlDescriptor()

        #expect(descriptor?.powerKey == nil)
        #expect(descriptor?.levelKey == "level")
        #expect(descriptor?.isOn == true)
        #expect(descriptor?.percentage == 50)
    }

    @Test
    func drivingLightControlDescriptorIsNilForNonLightDevices() {
        let device = TestSupport.makeDevice(
            uniqueId: "shutter-1",
            name: "Living Room",
            usage: "shutter",
            data: ["level": .number(40)]
        )

        #expect(device.drivingLightControlDescriptor() == nil)
    }

    @Test
    func observationEquivalenceIgnoresUpdatedAtAndUnrelatedMetadata() {
        let baseline = TestSupport.makeDevice(
            uniqueId: "light-7",
            name: "Patio",
            usage: "light",
            data: ["on": .bool(true), "level": .number(70)],
            metadata: [
                "level": .object(["min": .number(0), "max": .number(100)]),
                "heartbeat": .number(1)
            ]
        )

        var changed = baseline
        changed.updatedAt = baseline.updatedAt.addingTimeInterval(5)
        changed.metadata = [
            "level": .object(["min": .number(0), "max": .number(100)]),
            "heartbeat": .number(2)
        ]

        #expect(baseline.isEquivalentForObservation(to: changed))
    }

    @Test
    func observationEquivalenceDetectsMeaningfulControlChange() {
        let baseline = TestSupport.makeDevice(
            uniqueId: "light-8",
            name: "Garage",
            usage: "light",
            data: ["on": .bool(false), "level": .number(20)],
            metadata: ["level": .object(["min": .number(0), "max": .number(100)])]
        )

        var changed = baseline
        changed.data["level"] = .number(65)

        #expect(!baseline.isEquivalentForObservation(to: changed))
    }

    @Test
    func favoritesEquivalenceIgnoresUpdatedAtButTracksVisibleStatus() {
        let baseline = TestSupport.makeDevice(
            uniqueId: "window-1",
            name: "Kitchen Window",
            usage: "window",
            isFavorite: true,
            dashboardOrder: 0,
            data: ["open": .bool(false)]
        )

        var timeOnlyChange = baseline
        timeOnlyChange.updatedAt = baseline.updatedAt.addingTimeInterval(20)
        #expect(baseline.isEquivalentForFavorites(to: timeOnlyChange))

        var statusChange = baseline
        statusChange.data["open"] = .bool(true)
        #expect(!baseline.isEquivalentForFavorites(to: statusChange))
    }
}
