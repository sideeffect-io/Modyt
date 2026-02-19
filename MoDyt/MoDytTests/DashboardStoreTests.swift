import Testing
@testable import MoDyt

@MainActor
struct DashboardStoreTests {
    @Test
    func dashboardDeviceDescriptionUsesResolvedGroupOverride() {
        let description = DashboardDeviceDescription(
            uniqueId: "thermo-1",
            name: "Thermostat",
            usage: "unknownThermostat",
            resolvedGroup: .boiler
        )

        #expect(description.group == .boiler)
    }

    @Test
    func dashboardDeviceDescriptionFallsBackToUsageWhenNoOverride() {
        let description = DashboardDeviceDescription(
            uniqueId: "light-1",
            name: "Light",
            usage: "light"
        )

        #expect(description.group == .light)
    }

    @Test
    func favoritesStreamUpdatesState() async {
        let streamBox = BufferedStreamBox<[DashboardDeviceDescription]>()
        let store = DashboardStore(
            dependencies: .init(
                observeFavorites: { streamBox.stream },
                reorderFavorite: { _, _ in },
                refreshAll: {}
            )
        )

        store.send(.onAppear)
        streamBox.yield([
            DashboardDeviceDescription(uniqueId: "a", name: "A", usage: "light"),
            DashboardDeviceDescription(uniqueId: "b", name: "B", usage: "light"),
            DashboardDeviceDescription(uniqueId: "c", name: "C", usage: "light")
        ])
        let didReceiveFavorites = await waitUntil {
            store.state.favoriteDevices.map(\.uniqueId) == ["a", "b", "c"]
        }
        streamBox.finish()

        #expect(didReceiveFavorites)
        #expect(store.state.favoriteDevices.map(\.uniqueId) == ["a", "b", "c"])
    }

    @Test
    func onAppearStartsObservationOnlyOnce() async {
        let streamBox = BufferedStreamBox<[DashboardDeviceDescription]>()
        let observeCounter = LockedCounter()
        let store = DashboardStore(
            dependencies: .init(
                observeFavorites: {
                    observeCounter.increment()
                    return streamBox.stream
                },
                reorderFavorite: { _, _ in },
                refreshAll: {}
            )
        )

        store.send(.onAppear)
        store.send(.onAppear)
        let observedOnce = await waitUntil {
            observeCounter.value == 1
        }

        #expect(observedOnce)
        #expect(observeCounter.value == 1)
    }

    @Test
    func reorderAndRefreshDispatchEffects() async {
        let recorder = TestRecorder<String>()
        let store = DashboardStore(
            dependencies: .init(
                observeFavorites: {
                    AsyncStream { continuation in
                        continuation.finish()
                    }
                },
                reorderFavorite: { sourceId, targetId in
                    await recorder.record("reorder:\(sourceId)->\(targetId)")
                },
                refreshAll: {
                    await recorder.record("refresh")
                }
            )
        )

        store.send(.reorderFavorite("device-1", "device-2"))
        store.send(.refreshRequested)
        let didDispatch = await waitUntil {
            let entries = await recorder.values
            return entries.contains("reorder:device-1->device-2")
                && entries.contains("refresh")
        }

        #expect(didDispatch)
        let entries = await recorder.values
        #expect(entries.contains("reorder:device-1->device-2"))
        #expect(entries.contains("refresh"))
    }

    @Test
    func observationRestartsAfterStreamCompletion() async {
        let firstStream = BufferedStreamBox<[DashboardDeviceDescription]>()
        let secondStream = BufferedStreamBox<[DashboardDeviceDescription]>()
        let observeCounter = Counter()

        let store = DashboardStore(
            dependencies: .init(
                observeFavorites: {
                    await observeCounter.increment()
                    let attempt = await observeCounter.value
                    switch attempt {
                    case 1:
                        return firstStream.stream
                    case 2:
                        return secondStream.stream
                    default:
                        return AsyncStream { continuation in
                            continuation.finish()
                        }
                    }
                },
                reorderFavorite: { _, _ in },
                refreshAll: {}
            )
        )

        store.send(.onAppear)
        firstStream.yield([
            DashboardDeviceDescription(uniqueId: "first", name: "First", usage: "light")
        ])
        let didLoadFirst = await waitUntil {
            store.state.favoriteDevices.map(\.uniqueId) == ["first"]
        }
        #expect(didLoadFirst)
        #expect(store.state.favoriteDevices.map(\.uniqueId) == ["first"])

        firstStream.finish()
        let firstFinished = await waitUntil {
            await observeCounter.value >= 1
        }
        #expect(firstFinished)

        store.send(.onAppear)
        secondStream.yield([
            DashboardDeviceDescription(uniqueId: "second", name: "Second", usage: "light")
        ])
        let didLoadSecond = await waitUntil {
            store.state.favoriteDevices.map(\.uniqueId) == ["second"]
        }

        #expect(didLoadSecond)
        #expect(await observeCounter.value == 2)
        #expect(store.state.favoriteDevices.map(\.uniqueId) == ["second"])
    }
}
