import Foundation
import Testing
@testable import MoDyt

struct GroupRepositoryTests {
    @Test
    func metadataBeforeMembershipKeepsMetadataAndCanonicalizesMembers() async throws {
        let databasePath = testTemporarySQLitePath("group-repository-tests")
        defer { try? FileManager.default.removeItem(atPath: databasePath) }

        let repository = GroupRepository.makeGroupRepository(databasePath: databasePath)

        try await repository.upsertMetadata([
            GroupMetadataUpsert(
                id: "kitchen",
                name: "Kitchen",
                usage: "light",
                picto: "lightbulb",
                isGroupUser: true,
                isGroupAll: false
            )
        ])
        try await repository.upsertMembership([
            GroupMembershipUpsert(
                id: "kitchen",
                memberIdentifiers: [
                    .init(deviceId: 2, endpointId: 2),
                    .init(deviceId: 1, endpointId: 3),
                    .init(deviceId: 2, endpointId: 2),
                    .init(deviceId: 1, endpointId: 1),
                ]
            )
        ])

        let stored = try await repository.get("kitchen")

        #expect(stored?.name == "Kitchen")
        #expect(stored?.usage == "light")
        #expect(stored?.picto == "lightbulb")
        #expect(stored?.isGroupUser == true)
        #expect(stored?.isGroupAll == false)
        #expect(stored?.memberIdentifiers == [
            .init(deviceId: 1, endpointId: 1),
            .init(deviceId: 1, endpointId: 3),
            .init(deviceId: 2, endpointId: 2),
        ])
    }

    @Test
    func membershipBeforeMetadataCreatesPlaceholderThenMetadataOverwritesIt() async throws {
        let databasePath = testTemporarySQLitePath("group-repository-tests")
        defer { try? FileManager.default.removeItem(atPath: databasePath) }

        let repository = GroupRepository.makeGroupRepository(databasePath: databasePath)

        try await repository.upsertMembership([
            GroupMembershipUpsert(
                id: "42",
                memberIdentifiers: [
                    .init(deviceId: 9, endpointId: 2),
                    .init(deviceId: 3, endpointId: 1),
                ]
            )
        ])

        let placeholder = try await repository.get("42")
        #expect(placeholder?.name == "Group 42")
        #expect(placeholder?.usage == "unknown")
        #expect(placeholder?.isGroupUser == false)

        try await repository.upsertMetadata([
            GroupMetadataUpsert(
                id: "42",
                name: "Bedroom",
                usage: "shutter",
                picto: nil,
                isGroupUser: true,
                isGroupAll: true
            )
        ])

        let stored = try await repository.get("42")

        #expect(stored?.name == "Bedroom")
        #expect(stored?.usage == "shutter")
        #expect(stored?.isGroupUser == true)
        #expect(stored?.isGroupAll == true)
        #expect(stored?.memberIdentifiers == [
            .init(deviceId: 3, endpointId: 1),
            .init(deviceId: 9, endpointId: 2),
        ])
    }
}
