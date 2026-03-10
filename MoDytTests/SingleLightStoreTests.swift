import Foundation
import Testing
@testable import MoDyt

struct DrivingLightControlDescriptorTests {
    @Test
    func descriptorPrefersLevelAndOnKeys() {
        let device = Self.makeLightDevice(
            identifier: .init(deviceId: 10, endpointId: 1),
            data: [
                "state": .bool(false),
                "on": .bool(true),
                "position": .number(25),
                "level": .number(40),
                "colorXY": .number(645_878_559),
                "colorMode": .string("XY"),
            ]
        )

        let descriptor = device.drivingLightControlDescriptor()

        #expect(descriptor?.powerKey == "on")
        #expect(descriptor?.levelKey == "level")
        #expect(descriptor?.isOn == true)
        #expect(descriptor?.level == 40)
        #expect(descriptor?.color?.key == "colorXY")
        #expect(descriptor?.color?.modeKey == nil)
        #expect(descriptor?.color?.modeValue == nil)
        #expect(abs((descriptor?.normalizedColor ?? 0) - 0.8356020111378358) < 0.0001)
    }

    @Test
    func rawLevelMappingRoundsAgainstConfiguredRange() {
        let descriptor = DrivingLightControlDescriptor(
            powerKey: "on",
            levelKey: "level",
            isOn: true,
            level: 44,
            range: 10...90,
            color: nil
        )

        #expect(descriptor.rawLevel(forNormalizedLevel: 0) == 10)
        #expect(descriptor.rawLevel(forNormalizedLevel: 0.5) == 50)
        #expect(descriptor.rawLevel(forNormalizedLevel: 1) == 90)
        #expect(abs(descriptor.normalizedLevel(forRawLevel: 50) - 0.5) < 0.0001)
    }

    @Test(arguments: [
        PackedXYExpectation(
            normalizedHue: 0,
            expectedRawValue: 1_417_389_015,
            expectedX: 0.64,
            expectedY: 0.33
        ),
        PackedXYExpectation(
            normalizedHue: 1.0 / 3.0,
            expectedRawValue: 2_577_026_253,
            expectedX: 0.30,
            expectedY: 0.60
        ),
        PackedXYExpectation(
            normalizedHue: 2.0 / 3.0,
            expectedRawValue: 257_697_382,
            expectedX: 0.15,
            expectedY: 0.06
        )
    ])
    func packedXYUsesStandardSRGBPrimaries(expectation: PackedXYExpectation) {
        let descriptor = Self.makeColorDescriptor(rawValue: 0)

        let rawValue = descriptor.rawValue(forNormalizedValue: expectation.normalizedHue)
        let xy = Self.unpackXY(rawValue)

        #expect(rawValue == expectation.expectedRawValue)
        #expect(abs(xy.x - expectation.expectedX) < 0.0001)
        #expect(abs(xy.y - expectation.expectedY) < 0.0001)
    }

    @Test
    func packedXYUsesZigbeeScalingWithXInLowWordAndYInHighWord() {
        let descriptor = Self.makeColorDescriptor(rawValue: 0)

        let rawValue = descriptor.rawValue(forNormalizedValue: 0.5)
        let xWord = rawValue & 0xFFFF
        let yWord = (rawValue >> 16) & 0xFFFF

        #expect(rawValue == 1_411_922_306)
        #expect(xWord == 14_722)
        #expect(yWord == 21_544)
        #expect(abs(Double(xWord) / 65_536.0 - 0.22464749252514266) < 0.0001)
        #expect(abs(Double(yWord) / 65_536.0 - 0.3287309730905137) < 0.0001)
    }

    @Test(arguments: [
        CapturedXYExpectation(rawValue: 645_878_559, expectedNormalizedHue: 0.8356020111378358),
        CapturedXYExpectation(rawValue: 699_109_354, expectedNormalizedHue: 0.9189975148460361)
    ])
    func capturedTydomXYValuesDecodeWithZigbeeScaling(expectation: CapturedXYExpectation) {
        let descriptor = Self.makeColorDescriptor(rawValue: expectation.rawValue)

        #expect(abs(descriptor.normalizedValue - expectation.expectedNormalizedHue) < 0.0001)
    }

    struct PackedXYExpectation: Sendable {
        let normalizedHue: Double
        let expectedRawValue: Int
        let expectedX: Double
        let expectedY: Double
    }

    struct CapturedXYExpectation: Sendable {
        let rawValue: Int
        let expectedNormalizedHue: Double
    }

    private static func makeColorDescriptor(rawValue: Int) -> DrivingLightColorDescriptor {
        DrivingLightColorDescriptor(
            key: "colorXY",
            modeKey: nil,
            modeValue: nil,
            value: Double(rawValue),
            range: 0...4_294_967_294
        )
    }

    private static func unpackXY(_ rawValue: Int) -> (x: Double, y: Double) {
        let xWord = rawValue & 0xFFFF
        let yWord = (rawValue >> 16) & 0xFFFF
        return (
            x: Double(xWord) / 65_536.0,
            y: Double(yWord) / 65_536.0
        )
    }

    private static func makeLightDevice(
        identifier: DeviceIdentifier,
        data: [String: JSONValue]
    ) -> Device {
        Device(
            id: identifier,
            deviceId: identifier.deviceId,
            endpointId: identifier.endpointId,
            name: "Light",
            usage: "light",
            kind: "light",
            data: data,
            metadata: [
                "level": .object([
                    "min": .number(0),
                    "max": .number(100)
                ]),
                "colorXY": .object([
                    "min": .number(0),
                    "max": .number(4_294_967_294)
                ]),
                "colorMode": .object([
                    "permission": .string("r")
                ])
            ],
            isFavorite: false,
            dashboardOrder: nil,
            updatedAt: Date()
        )
    }
}

struct SingleLightReducerTests {
    private static let initialColorXY = 645_878_559
    private static let committedColorXY = 1_411_922_306
    private static let committedNormalizedColor = 0.49999760920696135
    private static let deviceId = DeviceIdentifier(deviceId: 10, endpointId: 1)
    private static let descriptor = DrivingLightControlDescriptor(
        powerKey: "on",
        levelKey: "level",
        isOn: true,
        level: 20,
        range: 0...100,
        color: DrivingLightColorDescriptor(
            key: "colorXY",
            modeKey: nil,
            modeValue: nil,
            value: Double(initialColorXY),
            range: 0...4_294_967_294
        )
    )

    @Test
    func descriptorObservationStartsFeature() {
        var stateMachine = SingleLightStore.StateMachine(
            state: .featureIsIdle(deviceId: Self.deviceId, descriptor: nil)
        )

        let effects = stateMachine.reduce(
            SingleLightEvent.descriptorWasReceived(Self.descriptor)
        )

        #expect(effects.isEmpty)
        #expect(
            stateMachine.state == SingleLightState.featureIsStarted(
                deviceId: Self.deviceId,
                descriptor: Self.descriptor
            )
        )
    }

    @Test
    func committedLevelSendsACommandAndMovesToPendingState() {
        var stateMachine = SingleLightStore.StateMachine(
            state: .featureIsStarted(deviceId: Self.deviceId, descriptor: Self.descriptor)
        )

        let effects = stateMachine.reduce(SingleLightEvent.levelWasCommitted(0.75))

        #expect(effects == [
            SingleLightEffect.sendCommand(
                .data(
                    LightGatewayCommandRequest(
                        deviceId: Self.deviceId,
                        signalName: "level",
                        value: LightGatewayCommandValue.int(75)
                    )
                )
            )
        ])

        #expect(
            stateMachine.state == SingleLightState.commandIsPending(
                deviceId: Self.deviceId,
                descriptor: Self.descriptor,
                pendingCommand: SingleLightPendingCommand(
                    command: .data(
                        LightGatewayCommandRequest(
                            deviceId: Self.deviceId,
                            signalName: "level",
                            value: LightGatewayCommandValue.int(75)
                        )
                    ),
                    presentation: SingleLightPendingPresentation(
                        normalizedLevel: 0.75,
                        isOn: true,
                        normalizedColor: Self.descriptor.normalizedColor
                    ),
                    expectedPowerState: nil,
                    expectedLevel: 75,
                    expectedColor: nil
                )
            )
        )
    }

    @Test
    func committedColorSendsACommandAndMovesToPendingState() {
        var stateMachine = SingleLightStore.StateMachine(
            state: .featureIsStarted(deviceId: Self.deviceId, descriptor: Self.descriptor)
        )

        let effects = stateMachine.reduce(SingleLightEvent.colorWasCommitted(0.5))

        #expect(effects == [
            SingleLightEffect.sendCommand(
                .color(
                    LightGatewayColorCommandRequest(
                        deviceId: Self.deviceId,
                        signalName: "colorXY",
                        value: .int(Self.committedColorXY),
                        colorModeSignalName: nil,
                        colorModeValue: nil
                    )
                )
            )
        ])

        #expect(
            stateMachine.state == SingleLightState.commandIsPending(
                deviceId: Self.deviceId,
                descriptor: Self.descriptor,
                pendingCommand: SingleLightPendingCommand(
                    command: .color(
                        LightGatewayColorCommandRequest(
                            deviceId: Self.deviceId,
                            signalName: "colorXY",
                            value: .int(Self.committedColorXY),
                            colorModeSignalName: nil,
                            colorModeValue: nil
                        )
                    ),
                    presentation: SingleLightPendingPresentation(
                        normalizedLevel: Self.descriptor.normalizedLevel,
                        isOn: true,
                        normalizedColor: Self.committedNormalizedColor
                    ),
                    expectedPowerState: nil,
                    expectedLevel: nil,
                    expectedColor: Self.committedColorXY
                )
            )
        )
    }

    @Test
    func matchingObservationClearsPendingState() {
        let pendingCommand = SingleLightPendingCommand(
            command: .data(
                LightGatewayCommandRequest(
                    deviceId: Self.deviceId,
                    signalName: "level",
                    value: LightGatewayCommandValue.int(75)
                )
            ),
            presentation: SingleLightPendingPresentation(
                normalizedLevel: 0.75,
                isOn: true,
                normalizedColor: Self.descriptor.normalizedColor
            ),
            expectedPowerState: nil,
            expectedLevel: 75,
            expectedColor: nil
        )
        var stateMachine = SingleLightStore.StateMachine(
            state: .commandIsPending(
                deviceId: Self.deviceId,
                descriptor: Self.descriptor,
                pendingCommand: pendingCommand
            )
        )

        let effects = stateMachine.reduce(
            SingleLightEvent.descriptorWasReceived(
                DrivingLightControlDescriptor(
                    powerKey: "on",
                    levelKey: "level",
                    isOn: true,
                    level: 75,
                    range: 0...100,
                    color: Self.descriptor.color
                )
            )
        )

        #expect(effects.isEmpty)
        #expect(
            stateMachine.state == SingleLightState.featureIsStarted(
                deviceId: Self.deviceId,
                descriptor: DrivingLightControlDescriptor(
                    powerKey: "on",
                    levelKey: "level",
                    isOn: true,
                    level: 75,
                    range: 0...100,
                    color: Self.descriptor.color
                )
            )
        )
    }
}

@MainActor
struct SingleLightStoreTests {
    private let initialColorXY = 645_878_559
    private let intermediateColorXY = 699_109_354
    private let committedColorXY = 1_411_922_306
    private let initialNormalizedColor = 0.8356020111378358
    private let committedNormalizedColor = 0.49999760920696135
    private let deviceId = DeviceIdentifier(deviceId: 10, endpointId: 1)

    @Test
    func startIsIdempotent() async {
        let starts = ObservationStartRecorder()
        let store = SingleLightStore(
            deviceId: deviceId,
            dependencies: .init(
                observeLight: { _ in
                    await starts.record()
                    return AsyncStream { continuation in
                        continuation.finish()
                    }
                },
                sendCommand: { _ in }
            )
        )

        store.start()
        store.start()
        #expect(await waitUntilAsync {
            await starts.count() > 0
        })

        #expect(await starts.count() == 1)
    }

    @Test
    func observationUpdatesDescriptor() async {
        let streamBox = DeviceStreamBox()
        let store = makeStore(streamBox: streamBox)

        streamBox.yield(makeLightDevice(level: 20, isOn: true))

        let didObserve = await waitUntil {
            abs(store.displayedNormalizedLevel - 0.2) < 0.0001 && store.displayedIsOn
        }

        #expect(didObserve)
        #expect(store.descriptor?.levelKey == "level")
        #expect(store.displayedIsOn)
    }

    @Test
    func levelCommitKeepsPendingPresentationUntilObservationMatches() async {
        let streamBox = DeviceStreamBox()
        let commands = RecordedLightGatewayCommands()
        let store = makeStore(
            streamBox: streamBox,
            commands: commands
        )

        streamBox.yield(makeLightDevice(level: 20, isOn: true))
        #expect(await waitUntil {
            abs(store.displayedNormalizedLevel - 0.2) < 0.0001
        })

        store.send(.levelWasCommitted(0.75))

        #expect(await waitUntil {
            abs(store.displayedNormalizedLevel - 0.75) < 0.0001
        })
        #expect(await waitUntilAsync {
            await commands.values().count == 1
        })
        #expect(await commands.values() == [
            .data(
                .init(
                    deviceId: deviceId,
                    signalName: "level",
                    value: .int(75)
                )
            )
        ])

        streamBox.yield(makeLightDevice(level: 25, isOn: true))
        #expect(await waitUntil {
            abs((store.descriptor?.level ?? 0) - 25) < 0.0001
        })
        #expect(abs(store.displayedNormalizedLevel - 0.75) < 0.0001)

        streamBox.yield(makeLightDevice(level: 75, isOn: true))
        #expect(await waitUntil {
            if case .featureIsStarted = store.state {
                return abs(store.displayedNormalizedLevel - 0.75) < 0.0001
            }
            return false
        })
    }

    @Test
    func colorCommitKeepsPendingPresentationUntilObservationMatches() async {
        let streamBox = DeviceStreamBox()
        let commands = RecordedLightGatewayCommands()
        let store = makeStore(
            streamBox: streamBox,
            commands: commands
        )

        streamBox.yield(makeLightDevice(level: 20, isOn: true, colorXY: initialColorXY))
        #expect(await waitUntil {
            store.isColorInteractionEnabled
                && abs(store.displayedNormalizedColor - initialNormalizedColor) < 0.0001
        })

        store.send(.colorWasCommitted(0.5))

        #expect(await waitUntil {
            abs(store.displayedNormalizedColor - committedNormalizedColor) < 0.0001
        })
        #expect(await waitUntilAsync {
            await commands.values().count == 1
        })
        #expect(await commands.values() == [
            .color(
                .init(
                    deviceId: deviceId,
                    signalName: "colorXY",
                    value: .int(committedColorXY),
                    colorModeSignalName: nil,
                    colorModeValue: nil
                )
            )
        ])

        streamBox.yield(makeLightDevice(level: 20, isOn: true, colorXY: intermediateColorXY))
        #expect(await waitUntil {
            abs((store.descriptor?.color?.value ?? 0) - Double(intermediateColorXY)) < 0.0001
        })
        #expect(abs(store.displayedNormalizedColor - committedNormalizedColor) < 0.0001)

        streamBox.yield(makeLightDevice(level: 20, isOn: true, colorXY: committedColorXY))
        #expect(await waitUntil {
            if case .featureIsStarted = store.state {
                return abs(store.displayedNormalizedColor - committedNormalizedColor) < 0.0001
            }
            return false
        })
    }

    @Test
    func powerFallbackUsesLevelExtremesWhenNoBooleanSignalExists() async {
        let streamBox = DeviceStreamBox()
        let commands = RecordedLightGatewayCommands()
        let store = SingleLightStore(
            deviceId: deviceId,
            dependencies: .init(
                observeLight: { _ in streamBox.stream },
                sendCommand: { request in
                    await commands.record(request)
                }
            )
        )
        store.start()

        streamBox.yield(makeLevelOnlyLightDevice(level: 0))
        #expect(await waitUntil {
            store.descriptor != nil && store.descriptor?.powerKey == nil
        })

        store.send(.powerWasSet(true))
        #expect(await waitUntilAsync {
            await commands.values().count == 1
        })

        #expect(await commands.values() == [
            .data(
                .init(
                    deviceId: deviceId,
                    signalName: "level",
                    value: .int(100)
                )
            )
        ])
    }

    private func makeStore(
        streamBox: DeviceStreamBox,
        commands: RecordedLightGatewayCommands = RecordedLightGatewayCommands()
    ) -> SingleLightStore {
        let store = SingleLightStore(
            deviceId: deviceId,
            dependencies: .init(
                observeLight: { _ in streamBox.stream },
                sendCommand: { request in
                    await commands.record(request)
                }
            )
        )
        store.start()
        return store
    }

    private func makeLightDevice(level: Double, isOn: Bool, colorXY: Int = 645_878_559) -> Device {
        Device(
            id: deviceId,
            deviceId: deviceId.deviceId,
            endpointId: deviceId.endpointId,
            name: "Living room light",
            usage: "light",
            kind: "light",
            data: [
                "level": .number(level),
                "on": .bool(isOn),
                "colorXY": .number(Double(colorXY)),
                "colorMode": .string("XY")
            ],
            metadata: [
                "level": .object([
                    "min": .number(0),
                    "max": .number(100)
                ]),
                "colorXY": .object([
                    "min": .number(0),
                    "max": .number(4_294_967_294)
                ]),
                "colorMode": .object([
                    "permission": .string("r")
                ])
            ],
            isFavorite: false,
            dashboardOrder: nil,
            updatedAt: Date()
        )
    }

    private func makeLevelOnlyLightDevice(level: Double) -> Device {
        Device(
            id: deviceId,
            deviceId: deviceId.deviceId,
            endpointId: deviceId.endpointId,
            name: "TV light",
            usage: "light",
            kind: "light",
            data: [
                "level": .number(level)
            ],
            metadata: [
                "level": .object([
                    "min": .number(0),
                    "max": .number(100)
                ])
            ],
            isFavorite: false,
            dashboardOrder: nil,
            updatedAt: Date()
        )
    }
}

@MainActor
private func waitUntil(
    cycles: Int = 40,
    condition: @escaping @MainActor () -> Bool
) async -> Bool {
    for _ in 0..<cycles {
        if condition() {
            return true
        }
        await Task.yield()
    }
    return condition()
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

private actor ObservationStartRecorder {
    private var starts = 0

    func record() {
        starts += 1
    }

    func count() -> Int {
        starts
    }
}

private actor RecordedLightGatewayCommands {
    private var entries: [SingleLightGatewayCommand] = []

    func record(_ command: SingleLightGatewayCommand) {
        entries.append(command)
    }

    func values() -> [SingleLightGatewayCommand] {
        entries
    }
}

private final class DeviceStreamBox: @unchecked Sendable {
    let stream: AsyncStream<Device?>

    private let continuation: AsyncStream<Device?>.Continuation

    init() {
        var localContinuation: AsyncStream<Device?>.Continuation?
        self.stream = AsyncStream { continuation in
            localContinuation = continuation
        }
        self.continuation = localContinuation!
    }

    func yield(_ value: Device?) {
        continuation.yield(value)
    }
}
