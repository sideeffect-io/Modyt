import Testing
@testable import MoDyt

struct GroupShutterReducerTests {
    struct TransitionCase: Sendable {
        let initial: GroupShutterState
        let event: GroupShutterEvent
        let expected: GroupShutterState
        let expectedEffects: [GroupShutterEffect]
    }

    private static let id10 = DeviceIdentifier(deviceId: 10, endpointId: 1)
    private static let id11 = DeviceIdentifier(deviceId: 11, endpointId: 1)

    @Test(arguments: transitionCases)
    func reducerAppliesConfiguredTransition(_ transition: TransitionCase) {
        let transitionResult = GroupShutterStore.StateMachine.reduce(
            transition.initial,
            transition.event
        )

        #expect(transitionResult.state == transition.expected)
        #expect(transitionResult.effects == transition.expectedEffects)
    }

    private static let transitionCases: [TransitionCase] = [
        .init(
            initial: .featureIsIdle(deviceIds: [id10, id11]),
            event: .targetWasSetInApp(target: 75),
            expected: .featureIsIdle(deviceIds: [id10, id11]),
            expectedEffects: [
                .sendCommand(position: 75),
                .persistTarget(target: 75),
            ]
        ),
        .init(
            initial: .featureIsIdle(deviceIds: []),
            event: .targetWasSetInApp(target: 75),
            expected: .featureIsIdle(deviceIds: []),
            expectedEffects: []
        ),
    ]
}

@MainActor
struct GroupShutterStoreTests {
    private let id10 = DeviceIdentifier(deviceId: 10, endpointId: 1)
    private let id11 = DeviceIdentifier(deviceId: 11, endpointId: 1)

    @Test
    func startIsANoOp() async {
        let commands = RecordedGroupShutterCommands()
        let targets = RecordedGroupShutterTargets()

        let store = GroupShutterStore(
            deviceIds: [id10, id11],
            sendCommand: .init(
                sendCommand: { deviceIds, position in
                    await commands.record(deviceIds: deviceIds, position: position)
                }
            ),
            persistTarget: .init(
                persistTarget: { deviceIds, target in
                    await targets.record(deviceIds: deviceIds, target: target)
                }
            )
        )

        store.start()
        await Task.yield()

        #expect(await commands.values().isEmpty)
        #expect(await targets.values().isEmpty)
    }

    @Test
    func targetWasSetInAppSendsCommandAndPersistsTargetForAllUniqueIds() async {
        let commands = RecordedGroupShutterCommands()
        let targets = RecordedGroupShutterTargets()

        let store = GroupShutterStore(
            deviceIds: [id10, id11],
            sendCommand: .init(
                sendCommand: { deviceIds, position in
                    await commands.record(deviceIds: deviceIds, position: position)
                }
            ),
            persistTarget: .init(
                persistTarget: { deviceIds, target in
                    await targets.record(deviceIds: deviceIds, target: target)
                }
            )
        )

        store.send(.targetWasSetInApp(target: 75))

        let didSend = await waitUntilAsync {
            let commandCount = await commands.values().count
            let targetCount = await targets.values().count
            return commandCount == 1 && targetCount == 1
        }
        #expect(didSend)

        #expect(await commands.values() == [
            .init(deviceIds: [id10, id11], position: 75)
        ])
        #expect(await targets.values() == [
            .init(deviceIds: [id10, id11], target: 75)
        ])
    }

    @Test
    func duplicateIdsAreDedupedBeforeEffectsRun() async {
        let commands = RecordedGroupShutterCommands()
        let targets = RecordedGroupShutterTargets()

        let store = GroupShutterStore(
            deviceIds: [id10, id11, id10, id11],
            sendCommand: .init(
                sendCommand: { deviceIds, position in
                    await commands.record(deviceIds: deviceIds, position: position)
                }
            ),
            persistTarget: .init(
                persistTarget: { deviceIds, target in
                    await targets.record(deviceIds: deviceIds, target: target)
                }
            )
        )

        store.send(.targetWasSetInApp(target: 25))

        let didSend = await waitUntilAsync {
            let commandCount = await commands.values().count
            let targetCount = await targets.values().count
            return commandCount == 1 && targetCount == 1
        }
        #expect(didSend)

        #expect(await commands.values() == [
            .init(deviceIds: [id10, id11], position: 25)
        ])
        #expect(await targets.values() == [
            .init(deviceIds: [id10, id11], target: 25)
        ])
    }

    @Test
    func emptyInputIsANoOp() async {
        let commands = RecordedGroupShutterCommands()
        let targets = RecordedGroupShutterTargets()

        let store = GroupShutterStore(
            deviceIds: [],
            sendCommand: .init(
                sendCommand: { deviceIds, position in
                    await commands.record(deviceIds: deviceIds, position: position)
                }
            ),
            persistTarget: .init(
                persistTarget: { deviceIds, target in
                    await targets.record(deviceIds: deviceIds, target: target)
                }
            )
        )

        store.send(.targetWasSetInApp(target: 50))
        await Task.yield()

        #expect(await commands.values().isEmpty)
        #expect(await targets.values().isEmpty)
    }

    private func waitUntilAsync(
        cycles: Int = 120,
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
}

private actor RecordedGroupShutterCommands {
    struct Entry: Sendable, Equatable {
        let deviceIds: [DeviceIdentifier]
        let position: Int
    }

    private var entries: [Entry] = []

    func record(deviceIds: [DeviceIdentifier], position: Int) {
        entries.append(.init(deviceIds: deviceIds, position: position))
    }

    func values() -> [Entry] {
        entries
    }
}

private actor RecordedGroupShutterTargets {
    struct Entry: Sendable, Equatable {
        let deviceIds: [DeviceIdentifier]
        let target: Int?
    }

    private var entries: [Entry] = []

    func record(deviceIds: [DeviceIdentifier], target: Int?) {
        entries.append(.init(deviceIds: deviceIds, target: target))
    }

    func values() -> [Entry] {
        entries
    }
}
