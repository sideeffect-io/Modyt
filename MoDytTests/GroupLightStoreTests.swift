import Testing
@testable import MoDyt

struct GroupLightReducerTests {
    struct TransitionCase: Sendable {
        let initial: GroupLightState
        let event: GroupLightEvent
        let expected: GroupLightState
        let expectedEffects: [GroupLightEffect]
    }

    private static let id10 = DeviceIdentifier(deviceId: 10, endpointId: 1)
    private static let id11 = DeviceIdentifier(deviceId: 11, endpointId: 1)

    @Test(arguments: transitionCases)
    func reducerAppliesConfiguredTransition(_ transition: TransitionCase) {
        let transitionResult = GroupLightStore.StateMachine.reduce(
            transition.initial,
            transition.event
        )

        #expect(transitionResult.state == transition.expected)
        #expect(transitionResult.effects == transition.expectedEffects)
    }

    private static let transitionCases: [TransitionCase] = [
        .init(
            initial: .featureIsIdle(deviceIds: [id10, id11]),
            event: .presetWasTapped(.half),
            expected: .featureIsIdle(deviceIds: [id10, id11]),
            expectedEffects: [
                .sendCommand(preset: .half)
            ]
        ),
        .init(
            initial: .featureIsIdle(deviceIds: []),
            event: .presetWasTapped(.on),
            expected: .featureIsIdle(deviceIds: []),
            expectedEffects: []
        ),
    ]
}

@MainActor
struct GroupLightStoreTests {
    private let id10 = DeviceIdentifier(deviceId: 10, endpointId: 1)
    private let id11 = DeviceIdentifier(deviceId: 11, endpointId: 1)

    @Test
    func startIsANoOp() async {
        let commands = RecordedGroupLightCommands()
        let store = GroupLightStore(
            deviceIds: [id10, id11],
            sendCommand: .init(
                sendCommand: { deviceIds, preset in
                    await commands.record(deviceIds: deviceIds, preset: preset)
                }
            )
        )

        store.start()
        await Task.yield()

        #expect(await commands.values().isEmpty)
    }

    @Test(arguments: LightPreset.allCases)
    func tappingPresetSendsDedupedIds(_ preset: LightPreset) async {
        let commands = RecordedGroupLightCommands()
        let store = GroupLightStore(
            deviceIds: [id10, id11, id10, id11],
            sendCommand: .init(
                sendCommand: { deviceIds, receivedPreset in
                    await commands.record(deviceIds: deviceIds, preset: receivedPreset)
                }
            )
        )

        store.send(.presetWasTapped(preset))

        let didSend = await waitUntilAsync {
            await commands.values().count == 1
        }
        #expect(didSend)
        #expect(await commands.values() == [
            .init(deviceIds: [id10, id11], preset: preset)
        ])
    }

    @Test
    func emptyInputIsANoOp() async {
        let commands = RecordedGroupLightCommands()
        let store = GroupLightStore(
            deviceIds: [],
            sendCommand: .init(
                sendCommand: { deviceIds, preset in
                    await commands.record(deviceIds: deviceIds, preset: preset)
                }
            )
        )

        store.send(.presetWasTapped(.off))
        await Task.yield()

        #expect(await commands.values().isEmpty)
    }
}

private func waitUntilAsync(
    cycles: Int = 80,
    condition: @escaping @Sendable () async -> Bool
) async -> Bool {
    for _ in 0..<cycles {
        if await condition() {
            return true
        }
        await Task.yield()
    }
    return await condition()
}

private actor RecordedGroupLightCommands {
    struct Entry: Sendable, Equatable {
        let deviceIds: [DeviceIdentifier]
        let preset: LightPreset
    }

    private var entries: [Entry] = []

    func record(deviceIds: [DeviceIdentifier], preset: LightPreset) {
        entries.append(.init(deviceIds: deviceIds, preset: preset))
    }

    func values() -> [Entry] {
        entries
    }
}
