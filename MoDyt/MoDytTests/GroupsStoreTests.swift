import Foundation
import Testing
@testable import MoDyt

@MainActor
struct GroupsStoreTests {
    @Test
    func updatesStateFromIncomingGroups() async {
        let store = GroupsStore(
            dependencies: .init(
                observeGroups: {
                    AsyncStream { continuation in
                        continuation.finish()
                    }
                },
                toggleFavorite: { _ in },
                refreshAll: {}
            )
        )

        store.send(.groupsUpdated([
            makeGroup(uniqueId: "group_2", groupId: 2, name: "Volets"),
            makeGroup(uniqueId: "group_1", groupId: 1, name: "Lumieres")
        ]))
        let didUpdate = await waitUntil {
            let names = store.state.groups.map(\.name)
            return names.count == 2 && Set(names) == Set(["Volets", "Lumieres"])
        }

        #expect(didUpdate)
        let names = store.state.groups.map(\.name)
        #expect(names.count == 2)
        #expect(Set(names) == Set(["Volets", "Lumieres"]))
    }

    @Test
    func toggleAndRefreshDispatchEffects() async {
        let recorder = TestRecorder<String>()
        let store = GroupsStore(
            dependencies: .init(
                observeGroups: {
                    AsyncStream { continuation in
                        continuation.finish()
                    }
                },
                toggleFavorite: { uniqueId in
                    await recorder.record("toggle:\(uniqueId)")
                },
                refreshAll: {
                    await recorder.record("refresh")
                }
            )
        )

        store.send(.toggleFavorite("group_10"))
        store.send(.refreshRequested)
        let didDispatch = await waitUntil {
            let entries = await recorder.values
            return entries.contains("toggle:group_10") && entries.contains("refresh")
        }

        #expect(didDispatch)
        let entries = await recorder.values
        #expect(entries.contains("toggle:group_10"))
        #expect(entries.contains("refresh"))
    }

    @Test
    func onAppearFiltersOutInternalGroups() async {
        let streamBox = BufferedStreamBox<[GroupRecord]>()
        let store = GroupsStore(
            dependencies: .init(
                observeGroups: { streamBox.stream },
                toggleFavorite: { _ in },
                refreshAll: {}
            )
        )

        store.send(.onAppear)
        streamBox.yield([
            makeGroup(uniqueId: "group_1", groupId: 1, name: "TOTAL", isGroupUser: false),
            makeGroup(uniqueId: "group_2", groupId: 2, name: "Volets Jour", isGroupUser: true),
            makeGroup(uniqueId: "group_3", groupId: 3, name: "Arriere TV", isGroupUser: true)
        ])
        let didFilter = await waitUntil {
            store.state.groups.map(\.name) == ["Arriere TV", "Volets Jour"]
        }

        #expect(didFilter)
        #expect(store.state.groups.map(\.name) == ["Arriere TV", "Volets Jour"])
    }

    private func makeGroup(
        uniqueId: String,
        groupId: Int,
        name: String,
        isGroupUser: Bool = true
    ) -> GroupRecord {
        GroupRecord(
            uniqueId: uniqueId,
            groupId: groupId,
            name: name,
            usage: "light",
            picto: nil,
            isGroupUser: isGroupUser,
            isGroupAll: false,
            memberUniqueIds: ["1_1"],
            isFavorite: false,
            favoriteOrder: nil,
            dashboardOrder: nil,
            updatedAt: Date()
        )
    }
}
