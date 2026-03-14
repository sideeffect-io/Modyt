import Foundation
import Testing
@testable import MoDyt

struct LightColorPresetTests {
    @Test
    func presetsExposeTheEightMeasuredChoicesInUIOrder() {
        let presets = LightColorCalibration.defaultProfile.presets

        #expect(presets.count == 8)
        #expect(presets.map(\.kind) == [
            .red,
            .pink,
            .violet,
            .blue,
            .cyan,
            .green,
            .yellow,
            .orange,
        ])
        #expect(presets.map(\.normalizedValue) == [1.0, 0.88, 0.76, 0.60, 0.46, 0.32, 0.18, 0.08])
        #expect(presets.map(\.miredTemperatureW) == [555, 345, 153, 153, 153, 153, 353, 555])
        #expect(presets.filter { $0.kind == .red }.count == 1)
    }

    @Test
    func nearestPresetWrapsRedAcrossTheNormalizedBoundary() {
        let calibration = LightColorCalibration.defaultProfile

        #expect(calibration.nearestPreset(for: 0.0)?.kind == .red)
        #expect(calibration.nearestPreset(for: 0.01)?.kind == .red)
        #expect(calibration.nearestPreset(for: 0.99)?.kind == .red)
        #expect(calibration.nearestPreset(for: 1.0)?.kind == .red)
    }

    @Test(arguments: [
        (LightColorPreset.Kind.red, 1.0),
        (.pink, 0.88),
        (.violet, 0.76),
        (.blue, 0.60),
        (.cyan, 0.46),
        (.green, 0.32),
        (.yellow, 0.18),
        (.orange, 0.08),
    ])
    func nearestPresetResolvesEachMeasuredAnchor(expectation: (LightColorPreset.Kind, Double)) {
        let calibration = LightColorCalibration.defaultProfile

        #expect(calibration.nearestPreset(for: expectation.1)?.kind == expectation.0)
    }

    @Test
    func nearestPresetForPackedXYUsesClosestObservedGatewayValue() {
        let calibration = LightColorCalibration.defaultProfile
        let observedGatewayPackedXY = 766_451_011

        #expect(calibration.nearestPreset(forPackedXY: observedGatewayPackedXY)?.kind == .violet)
    }
}

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
                "colorXY": .number(1_898_655_292),
                "miredTemperatureW": .number(345),
                "minMiredTemperatureW": .number(153),
                "maxMiredTemperatureW": .number(555),
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
        #expect(descriptor?.color?.temperatureKey == "miredTemperatureW")
        #expect(abs((descriptor?.normalizedColor ?? 0) - 0.88) < 0.0001)
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
        CalibratedColorExpectation(normalizedValue: 0.08, expectedRawValue: 2_385_996_822, expectedMiredTemperatureW: 555),
        CalibratedColorExpectation(normalizedValue: 0.18, expectedRawValue: 1_921_155_983, expectedMiredTemperatureW: 353),
        CalibratedColorExpectation(normalizedValue: 0.32, expectedRawValue: 740_343_536, expectedMiredTemperatureW: 153),
        CalibratedColorExpectation(normalizedValue: 0.46, expectedRawValue: 650_139_661, expectedMiredTemperatureW: 153),
        CalibratedColorExpectation(normalizedValue: 0.60, expectedRawValue: 585_108_043, expectedMiredTemperatureW: 153),
        CalibratedColorExpectation(normalizedValue: 0.76, expectedRawValue: 1_081_743_330, expectedMiredTemperatureW: 153),
        CalibratedColorExpectation(normalizedValue: 0.88, expectedRawValue: 1_898_655_292, expectedMiredTemperatureW: 345),
        CalibratedColorExpectation(normalizedValue: 1.00, expectedRawValue: 3_002_682_482, expectedMiredTemperatureW: 555),
    ])
    func packedXYUsesMeasuredCalibrationAnchors(expectation: CalibratedColorExpectation) {
        let descriptor = Self.makeColorDescriptor(rawValue: 0)

        let payload = descriptor.payload(forNormalizedValue: expectation.normalizedValue)
        let xy = Self.unpackXY(payload.rawValue)
        let expectedXY = Self.unpackXY(expectation.expectedRawValue)

        #expect(payload.rawValue == expectation.expectedRawValue)
        #expect(payload.miredTemperatureW == expectation.expectedMiredTemperatureW)
        #expect(abs(xy.x - expectedXY.x) < 0.0001)
        #expect(abs(xy.y - expectedXY.y) < 0.0001)
    }

    @Test
    func packedXYSnapsNearbySelectionsToMeasuredAnchors() {
        let descriptor = Self.makeColorDescriptor(rawValue: 0)

        let cyanPayload = descriptor.payload(forNormalizedValue: 0.455)
        let pinkPayload = descriptor.payload(forNormalizedValue: 0.865)

        #expect(cyanPayload.rawValue == 650_139_661)
        #expect(cyanPayload.miredTemperatureW == 153)
        #expect(pinkPayload.rawValue == 1_898_655_292)
        #expect(pinkPayload.miredTemperatureW == 345)
    }

    @Test(arguments: [
        CalibratedColorExpectation(normalizedValue: 0.08, expectedRawValue: 2_385_996_822, expectedMiredTemperatureW: 555),
        CalibratedColorExpectation(normalizedValue: 0.18, expectedRawValue: 1_921_155_983, expectedMiredTemperatureW: 353),
        CalibratedColorExpectation(normalizedValue: 0.32, expectedRawValue: 740_343_536, expectedMiredTemperatureW: 153),
        CalibratedColorExpectation(normalizedValue: 0.46, expectedRawValue: 650_139_661, expectedMiredTemperatureW: 153),
        CalibratedColorExpectation(normalizedValue: 0.60, expectedRawValue: 585_108_043, expectedMiredTemperatureW: 153),
        CalibratedColorExpectation(normalizedValue: 0.76, expectedRawValue: 1_081_743_330, expectedMiredTemperatureW: 153),
        CalibratedColorExpectation(normalizedValue: 0.88, expectedRawValue: 1_898_655_292, expectedMiredTemperatureW: 345),
        CalibratedColorExpectation(normalizedValue: 1.00, expectedRawValue: 3_002_682_482, expectedMiredTemperatureW: 555),
    ])
    func measuredCalibrationAnchorsDecodeBackToPickerStops(expectation: CalibratedColorExpectation) {
        let descriptor = Self.makeColorDescriptor(rawValue: expectation.expectedRawValue)

        #expect(abs(descriptor.normalizedValue - expectation.normalizedValue) < 0.0001)
    }

    struct CalibratedColorExpectation: Sendable {
        let normalizedValue: Double
        let expectedRawValue: Int
        let expectedMiredTemperatureW: Int?
    }

    private static func makeColorDescriptor(rawValue: Int) -> DrivingLightColorDescriptor {
        DrivingLightColorDescriptor(
            key: "colorXY",
            modeKey: nil,
            modeValue: nil,
            temperatureKey: "miredTemperatureW",
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
                "miredTemperatureW": .object([
                    "min": .number(153),
                    "max": .number(555)
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
    private static let calibration = DrivingLightColorDescriptor.packedXYCalibration
    private static let initialPreset = calibration.nearestPreset(for: 0.88)!
    private static let committedPreset = calibration.nearestPreset(for: 0.46)!
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
            temperatureKey: "miredTemperatureW",
            value: Double(initialPreset.packedXY),
            range: 0...4_294_967_294
        )
    )

    @Test
    func startedEmitsObservationEffect() {
        let transition = SingleLightStore.StateMachine.reduce(
            .idle(deviceId: Self.deviceId),
            .started
        )

        #expect(transition.state == .idle(deviceId: Self.deviceId))
        #expect(transition.effects == [.observeGateway])
    }

    @Test
    func descriptorObservationBuildsReadyState() {
        let transition = SingleLightStore.StateMachine.reduce(
            .idle(deviceId: Self.deviceId),
            .gatewayDescriptorWasReceived(Self.descriptor)
        )

        #expect(transition.effects.isEmpty)
        #expect(
            transition.state == .ready(
                context: SingleLightControlContext(
                    deviceId: Self.deviceId,
                    levelSignalName: "level",
                    rawLevelRange: 0...100,
                    color: SingleLightColorContext(
                        signalName: "colorXY",
                        modeSignalName: nil,
                        modeValue: nil,
                        temperatureSignalName: "miredTemperatureW"
                    )
                ),
                value: SingleLightValue(
                    normalizedLevel: 0.2,
                    color: SingleLightColorValue(
                        preset: Self.initialPreset,
                        packedXY: Self.initialPreset.packedXY,
                        miredTemperatureW: Self.initialPreset.miredTemperatureW
                    )
                ),
                colorHold: nil
            )
        )
    }

    @Test
    func descriptorWithoutLevelBecomesUnavailable() {
        let transition = SingleLightStore.StateMachine.reduce(
            .idle(deviceId: Self.deviceId),
            .gatewayDescriptorWasReceived(
                DrivingLightControlDescriptor(
                    powerKey: "on",
                    levelKey: nil,
                    isOn: true,
                    level: 20,
                    range: 0...100,
                    color: nil
                )
            )
        )

        #expect(transition.effects.isEmpty)
        #expect(transition.state == .unavailable(deviceId: Self.deviceId))
    }

    @Test
    func committedLevelMutatesLocalValueAndEmitsLevelCommand() {
        let transition = SingleLightStore.StateMachine.reduce(
            .ready(
                context: SingleLightControlContext(
                    deviceId: Self.deviceId,
                    levelSignalName: "level",
                    rawLevelRange: 0...100,
                    color: nil
                ),
                value: SingleLightValue(normalizedLevel: 0.2, color: nil),
                colorHold: nil
            ),
            .levelWasCommitted(0.75)
        )

        #expect(transition.effects == [
            .sendLevel(
                LightGatewayCommandRequest(
                    deviceId: Self.deviceId,
                    signalName: "level",
                    value: .int(75)
                )
            )
        ])
        #expect(
            transition.state == .ready(
                context: SingleLightControlContext(
                    deviceId: Self.deviceId,
                    levelSignalName: "level",
                    rawLevelRange: 0...100,
                    color: nil
                ),
                value: SingleLightValue(normalizedLevel: 0.75, color: nil),
                colorHold: nil
            )
        )
    }

    @Test
    func powerToggleUsesLevelExtremes() {
        let transition = SingleLightStore.StateMachine.reduce(
            .ready(
                context: SingleLightControlContext(
                    deviceId: Self.deviceId,
                    levelSignalName: "level",
                    rawLevelRange: 0...100,
                    color: nil
                ),
                value: SingleLightValue(normalizedLevel: 0.2, color: nil),
                colorHold: nil
            ),
            .powerWasToggled
        )

        #expect(transition.effects == [
            .sendLevel(
                LightGatewayCommandRequest(
                    deviceId: Self.deviceId,
                    signalName: "level",
                    value: .int(0)
                )
            )
        ])
        #expect(
            transition.state == .ready(
                context: SingleLightControlContext(
                    deviceId: Self.deviceId,
                    levelSignalName: "level",
                    rawLevelRange: 0...100,
                    color: nil
                ),
                value: SingleLightValue(normalizedLevel: 0, color: nil),
                colorHold: nil
            )
        )
    }

    @Test
    func presetSelectionStartsColorHoldAndEmitsColorPayload() {
        let transition = SingleLightStore.StateMachine.reduce(
            .ready(
                context: SingleLightControlContext(
                    deviceId: Self.deviceId,
                    levelSignalName: "level",
                    rawLevelRange: 0...100,
                    color: SingleLightColorContext(
                        signalName: "colorXY",
                        modeSignalName: nil,
                        modeValue: nil,
                        temperatureSignalName: "miredTemperatureW"
                    )
                ),
                value: SingleLightValue(
                    normalizedLevel: 0.2,
                    color: SingleLightColorValue(
                        preset: Self.initialPreset,
                        packedXY: Self.initialPreset.packedXY,
                        miredTemperatureW: Self.initialPreset.miredTemperatureW
                    )
                ),
                colorHold: nil
            ),
            .presetWasSelected(Self.committedPreset)
        )

        #expect(transition.effects == [
            .sendColor(
                LightGatewayColorCommandRequest(
                    deviceId: Self.deviceId,
                    signalName: "colorXY",
                    value: .int(Self.committedPreset.packedXY),
                    colorModeSignalName: nil,
                    colorModeValue: nil,
                    temperatureSignalName: nil,
                    temperatureValue: nil
                )
            ),
            .cancelColorHold(task: nil),
            .startColorHold,
        ])
        #expect(
            transition.state == .ready(
                context: SingleLightControlContext(
                    deviceId: Self.deviceId,
                    levelSignalName: "level",
                    rawLevelRange: 0...100,
                    color: SingleLightColorContext(
                        signalName: "colorXY",
                        modeSignalName: nil,
                        modeValue: nil,
                        temperatureSignalName: "miredTemperatureW"
                    )
                ),
                value: SingleLightValue(
                    normalizedLevel: 0.2,
                    color: SingleLightColorValue(
                        preset: Self.committedPreset,
                        packedXY: Self.committedPreset.packedXY,
                        miredTemperatureW: Self.committedPreset.miredTemperatureW
                    )
                ),
                colorHold: SingleLightColorHold(
                    timerTask: nil,
                    lastObservedColor: nil
                )
            )
        )
    }

    @Test
    func secondPresetSelectionCancelsExistingHoldAndResetsBufferedObservedColor() {
        let timerTask = Task<Void, Never> {}
        defer { timerTask.cancel() }

        let transition = SingleLightStore.StateMachine.reduce(
            .ready(
                context: SingleLightControlContext(
                    deviceId: Self.deviceId,
                    levelSignalName: "level",
                    rawLevelRange: 0...100,
                    color: SingleLightColorContext(
                        signalName: "colorXY",
                        modeSignalName: nil,
                        modeValue: nil,
                        temperatureSignalName: "miredTemperatureW"
                    )
                ),
                value: SingleLightValue(
                    normalizedLevel: 0.2,
                    color: SingleLightColorValue(
                        preset: Self.initialPreset,
                        packedXY: Self.initialPreset.packedXY,
                        miredTemperatureW: Self.initialPreset.miredTemperatureW
                    )
                ),
                colorHold: SingleLightColorHold(
                    timerTask: timerTask,
                    lastObservedColor: SingleLightColorValue(
                        preset: Self.initialPreset,
                        packedXY: Self.initialPreset.packedXY,
                        miredTemperatureW: Self.initialPreset.miredTemperatureW
                    )
                )
            ),
            .presetWasSelected(Self.committedPreset)
        )

        #expect(transition.effects == [
            .sendColor(
                LightGatewayColorCommandRequest(
                    deviceId: Self.deviceId,
                    signalName: "colorXY",
                    value: .int(Self.committedPreset.packedXY),
                    colorModeSignalName: nil,
                    colorModeValue: nil,
                    temperatureSignalName: nil,
                    temperatureValue: nil
                )
            ),
            .cancelColorHold(task: timerTask),
            .startColorHold,
        ])
        #expect(
            transition.state == .ready(
                context: SingleLightControlContext(
                    deviceId: Self.deviceId,
                    levelSignalName: "level",
                    rawLevelRange: 0...100,
                    color: SingleLightColorContext(
                        signalName: "colorXY",
                        modeSignalName: nil,
                        modeValue: nil,
                        temperatureSignalName: "miredTemperatureW"
                    )
                ),
                value: SingleLightValue(
                    normalizedLevel: 0.2,
                    color: SingleLightColorValue(
                        preset: Self.committedPreset,
                        packedXY: Self.committedPreset.packedXY,
                        miredTemperatureW: Self.committedPreset.miredTemperatureW
                    )
                ),
                colorHold: SingleLightColorHold(
                    timerTask: nil,
                    lastObservedColor: nil
                )
            )
        )
    }

    @Test
    func gatewayObservationDuringHoldBuffersObservedColorAndKeepsDisplayedPreset() {
        let transition = SingleLightStore.StateMachine.reduce(
            .ready(
                context: SingleLightControlContext(
                    deviceId: Self.deviceId,
                    levelSignalName: "level",
                    rawLevelRange: 0...100,
                    color: SingleLightColorContext(
                        signalName: "colorXY",
                        modeSignalName: nil,
                        modeValue: nil,
                        temperatureSignalName: "miredTemperatureW"
                    )
                ),
                value: SingleLightValue(
                    normalizedLevel: 0.2,
                    color: SingleLightColorValue(
                        preset: Self.committedPreset,
                        packedXY: Self.committedPreset.packedXY,
                        miredTemperatureW: Self.committedPreset.miredTemperatureW
                    )
                ),
                colorHold: SingleLightColorHold(
                    timerTask: nil,
                    lastObservedColor: nil
                )
            ),
            .gatewayDescriptorWasReceived(
                DrivingLightControlDescriptor(
                    powerKey: "on",
                    levelKey: "level",
                    isOn: true,
                    level: 60,
                    range: 0...100,
                    color: DrivingLightColorDescriptor(
                        key: "colorXY",
                        modeKey: nil,
                        modeValue: nil,
                        temperatureKey: "miredTemperatureW",
                        value: Double(Self.initialPreset.packedXY),
                        range: 0...4_294_967_294
                    )
                )
            )
        )

        #expect(transition.effects.isEmpty)
        #expect(
            transition.state == .ready(
                context: SingleLightControlContext(
                    deviceId: Self.deviceId,
                    levelSignalName: "level",
                    rawLevelRange: 0...100,
                    color: SingleLightColorContext(
                        signalName: "colorXY",
                        modeSignalName: nil,
                        modeValue: nil,
                        temperatureSignalName: "miredTemperatureW"
                    )
                ),
                value: SingleLightValue(
                    normalizedLevel: 0.6,
                    color: SingleLightColorValue(
                        preset: Self.committedPreset,
                        packedXY: Self.committedPreset.packedXY,
                        miredTemperatureW: Self.committedPreset.miredTemperatureW
                    )
                ),
                colorHold: SingleLightColorHold(
                    timerTask: nil,
                    lastObservedColor: SingleLightColorValue(
                        preset: Self.initialPreset,
                        packedXY: Self.initialPreset.packedXY,
                        miredTemperatureW: Self.initialPreset.miredTemperatureW
                    )
                )
            )
        )
    }

    @Test
    func colorHoldExpiredAppliesBufferedObservedColorAndClearsHold() {
        let transition = SingleLightStore.StateMachine.reduce(
            .ready(
                context: SingleLightControlContext(
                    deviceId: Self.deviceId,
                    levelSignalName: "level",
                    rawLevelRange: 0...100,
                    color: SingleLightColorContext(
                        signalName: "colorXY",
                        modeSignalName: nil,
                        modeValue: nil,
                        temperatureSignalName: "miredTemperatureW"
                    )
                ),
                value: SingleLightValue(
                    normalizedLevel: 0.2,
                    color: SingleLightColorValue(
                        preset: Self.committedPreset,
                        packedXY: Self.committedPreset.packedXY,
                        miredTemperatureW: Self.committedPreset.miredTemperatureW
                    )
                ),
                colorHold: SingleLightColorHold(
                    timerTask: nil,
                    lastObservedColor: SingleLightColorValue(
                        preset: Self.initialPreset,
                        packedXY: Self.initialPreset.packedXY,
                        miredTemperatureW: Self.initialPreset.miredTemperatureW
                    )
                )
            ),
            .colorHoldExpired
        )

        #expect(transition.effects.isEmpty)
        #expect(
            transition.state == .ready(
                context: SingleLightControlContext(
                    deviceId: Self.deviceId,
                    levelSignalName: "level",
                    rawLevelRange: 0...100,
                    color: SingleLightColorContext(
                        signalName: "colorXY",
                        modeSignalName: nil,
                        modeValue: nil,
                        temperatureSignalName: "miredTemperatureW"
                    )
                ),
                value: SingleLightValue(
                    normalizedLevel: 0.2,
                    color: SingleLightColorValue(
                        preset: Self.initialPreset,
                        packedXY: Self.initialPreset.packedXY,
                        miredTemperatureW: Self.initialPreset.miredTemperatureW
                    )
                ),
                colorHold: nil
            )
        )
    }

    @Test
    func unavailableObservationCancelsActiveColorHold() {
        let timerTask = Task<Void, Never> {}
        defer { timerTask.cancel() }

        let transition = SingleLightStore.StateMachine.reduce(
            .ready(
                context: SingleLightControlContext(
                    deviceId: Self.deviceId,
                    levelSignalName: "level",
                    rawLevelRange: 0...100,
                    color: SingleLightColorContext(
                        signalName: "colorXY",
                        modeSignalName: nil,
                        modeValue: nil,
                        temperatureSignalName: "miredTemperatureW"
                    )
                ),
                value: SingleLightValue(
                    normalizedLevel: 0.2,
                    color: SingleLightColorValue(
                        preset: Self.committedPreset,
                        packedXY: Self.committedPreset.packedXY,
                        miredTemperatureW: Self.committedPreset.miredTemperatureW
                    )
                ),
                colorHold: SingleLightColorHold(
                    timerTask: timerTask,
                    lastObservedColor: nil
                )
            ),
            .gatewayDescriptorWasReceived(nil)
        )

        #expect(transition.state == .unavailable(deviceId: Self.deviceId))
        #expect(transition.effects == [.cancelColorHold(task: timerTask)])
    }

    @Test
    func offStateObservationWithoutColorKeepsLastKnownColorAndContext() {
        let previousState = SingleLightState.ready(
            context: SingleLightControlContext(
                deviceId: Self.deviceId,
                levelSignalName: "level",
                rawLevelRange: 0...100,
                color: SingleLightColorContext(
                    signalName: "colorXY",
                    modeSignalName: nil,
                    modeValue: nil,
                    temperatureSignalName: "miredTemperatureW"
                )
            ),
            value: SingleLightValue(
                normalizedLevel: 0.46,
                color: SingleLightColorValue(
                    preset: Self.committedPreset,
                    packedXY: Self.committedPreset.packedXY,
                    miredTemperatureW: Self.committedPreset.miredTemperatureW
                )
            ),
            colorHold: nil
        )

        let transition = SingleLightStore.StateMachine.reduce(
            previousState,
            .gatewayDescriptorWasReceived(
                DrivingLightControlDescriptor(
                    powerKey: "on",
                    levelKey: "level",
                    isOn: false,
                    level: 0,
                    range: 0...100,
                    color: nil
                )
            )
        )

        #expect(transition.effects.isEmpty)
        #expect(
            transition.state == .ready(
                context: SingleLightControlContext(
                    deviceId: Self.deviceId,
                    levelSignalName: "level",
                    rawLevelRange: 0...100,
                    color: SingleLightColorContext(
                        signalName: "colorXY",
                        modeSignalName: nil,
                        modeValue: nil,
                        temperatureSignalName: "miredTemperatureW"
                    )
                ),
                value: SingleLightValue(
                    normalizedLevel: 0,
                    color: SingleLightColorValue(
                        preset: Self.committedPreset,
                        packedXY: Self.committedPreset.packedXY,
                        miredTemperatureW: Self.committedPreset.miredTemperatureW
                    )
                ),
                colorHold: nil
            )
        )
    }
}

@MainActor
struct SingleLightStoreTests {
    private let testColorHoldDuration: Duration = .milliseconds(20)
    private let calibration = DrivingLightColorDescriptor.packedXYCalibration
    private let initialColorXY = 1_898_655_292
    private let intermediateColorXY = 1_081_743_330
    private let committedColorXY = 650_139_661
    private let initialNormalizedColor = 0.88
    private let committedNormalizedColor = 0.46
    private let intermediateNormalizedColor = 0.76
    private let deviceId = DeviceIdentifier(deviceId: 10, endpointId: 1)

    private var committedPreset: LightColorPreset {
        calibration.nearestPreset(for: committedNormalizedColor)!
    }

    private var intermediatePreset: LightColorPreset {
        calibration.nearestPreset(for: intermediateNormalizedColor)!
    }

    @Test
    func startIsIdempotent() async {
        let starts = ObservationStartRecorder()
        let store = SingleLightStore(
            deviceId: deviceId,
            observeLight: .init(
                observeLight: {
                    await starts.record()
                    return AsyncStream { continuation in
                        continuation.finish()
                    }
                }
            ),
            sendCommand: .init(
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
    func observationBuildsReadyState() async {
        let streamBox = DeviceStreamBox()
        let store = makeStore(streamBox: streamBox)

        streamBox.yield(makeLightDevice(level: 20, isOn: true))

        #expect(await waitUntil {
            if case .ready(let context, let value, _) = store.state {
                return context.levelSignalName == "level"
                    && context.color?.signalName == "colorXY"
                    && abs(value.normalizedLevel - 0.2) < 0.0001
                    && value.color?.preset.kind == .pink
            }
            return false
        })
    }

    @Test
    func levelCommitUpdatesImmediatelyThenGatewayObservationOverwritesIt() async {
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
            abs(store.displayedNormalizedLevel - 0.25) < 0.0001
        })
    }

    @Test
    func presetSelectionBuffersIntermediateGatewayColorThenAppliesItAfterTheConfiguredHoldWindow() async {
        let streamBox = DeviceStreamBox()
        let commands = RecordedLightGatewayCommands()
        let store = makeStore(
            streamBox: streamBox,
            commands: commands
        )

        streamBox.yield(
            makeLightDevice(
                level: 20,
                isOn: true,
                colorXY: initialColorXY,
                miredTemperatureW: 345
            )
        )
        #expect(await waitUntil {
            store.selectedPresetKind == .pink
        })

        store.send(.presetWasSelected(committedPreset))

        #expect(await waitUntil {
            store.selectedPresetKind == committedPreset.kind
                && abs(store.displayedNormalizedColor - committedNormalizedColor) < 0.0001
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
                    colorModeValue: nil,
                    temperatureSignalName: nil,
                    temperatureValue: nil
                )
            )
        ])

        streamBox.yield(
            makeLightDevice(
                level: 20,
                isOn: true,
                colorXY: intermediateColorXY,
                miredTemperatureW: 153
            )
        )

        #expect(await waitUntil {
            store.selectedPresetKind == committedPreset.kind
                && abs(store.displayedNormalizedColor - committedNormalizedColor) < 0.0001
        })

        try? await Task.sleep(for: .milliseconds(50))

        #expect(await waitUntil {
            store.selectedPresetKind == intermediatePreset.kind
                && abs(store.displayedNormalizedColor - intermediateNormalizedColor) < 0.0001
        })
    }

    @Test
    func powerToggleUsesLevelShortcuts() async {
        let streamBox = DeviceStreamBox()
        let commands = RecordedLightGatewayCommands()
        let store = makeStore(
            streamBox: streamBox,
            commands: commands
        )

        streamBox.yield(makeLightDevice(level: 20, isOn: true))
        #expect(await waitUntil {
            store.displayedIsOn
        })

        store.send(.powerWasToggled)

        #expect(await waitUntil {
            store.displayedIsOn == false
                && abs(store.displayedNormalizedLevel - 0) < 0.0001
        })
        #expect(await waitUntilAsync {
            await commands.values().count == 1
        })
        #expect(await commands.values() == [
            .data(
                .init(
                    deviceId: deviceId,
                    signalName: "level",
                    value: .int(0)
                )
            )
        ])
    }

    @Test
    func offStateObservationWithoutColorKeepsTheLastKnownPreset() async {
        let streamBox = DeviceStreamBox()
        let store = makeStore(streamBox: streamBox)

        streamBox.yield(
            makeLightDevice(
                level: 20,
                isOn: true,
                colorXY: initialColorXY,
                miredTemperatureW: 345
            )
        )
        #expect(await waitUntil {
            store.selectedPresetKind == .pink
        })

        store.send(.presetWasSelected(committedPreset))
        #expect(await waitUntil {
            store.selectedPresetKind == committedPreset.kind
        })

        streamBox.yield(
            makeLightDevice(
                level: 0,
                isOn: false,
                reportsColor: false
            )
        )

        #expect(await waitUntil {
            store.displayedIsOn == false
                && store.isColorInteractionEnabled
                && store.selectedPresetKind == committedPreset.kind
        })
    }

    @Test
    func externalGatewayChangesUpdateTheUiWithoutAnyLocalIntent() async {
        let streamBox = DeviceStreamBox()
        let store = makeStore(streamBox: streamBox)

        streamBox.yield(makeLightDevice(level: 10, isOn: true))
        #expect(await waitUntil {
            abs(store.displayedNormalizedLevel - 0.1) < 0.0001
        })

        streamBox.yield(
            makeLightDevice(
                level: 60,
                isOn: true,
                colorXY: intermediateColorXY,
                miredTemperatureW: 153
            )
        )

        #expect(await waitUntil {
            abs(store.displayedNormalizedLevel - 0.6) < 0.0001
                && store.selectedPresetKind == intermediatePreset.kind
        })
    }

    @Test
    func nonPresetGatewayColorSnapsToTheClosestPreset() async {
        let streamBox = DeviceStreamBox()
        let store = makeStore(streamBox: streamBox)

        streamBox.yield(
            makeLightDevice(
                level: 45,
                isOn: true,
                colorXY: 766_451_011,
                miredTemperatureW: 153
            )
        )

        #expect(await waitUntil {
            abs(store.displayedNormalizedLevel - 0.45) < 0.0001
                && store.selectedPresetKind == .violet
                && abs(store.displayedNormalizedColor - 0.76) < 0.0001
        })
    }

    @Test
    func repeatedPresetSelectionsCancelAndReplaceThePreviousHold() async {
        let streamBox = DeviceStreamBox()
        let store = makeStore(streamBox: streamBox)

        streamBox.yield(
            makeLightDevice(
                level: 20,
                isOn: true,
                colorXY: initialColorXY,
                miredTemperatureW: 345
            )
        )
        #expect(await waitUntil {
            store.selectedPresetKind == .pink
        })

        store.send(.presetWasSelected(committedPreset))
        #expect(await waitUntil {
            store.selectedPresetKind == committedPreset.kind
        })

        streamBox.yield(
            makeLightDevice(
                level: 20,
                isOn: true,
                colorXY: committedColorXY,
                miredTemperatureW: 555
            )
        )

        #expect(await waitUntil {
            store.selectedPresetKind == committedPreset.kind
        })

        store.send(.presetWasSelected(intermediatePreset))
        #expect(await waitUntil {
            store.selectedPresetKind == intermediatePreset.kind
                && abs(store.displayedNormalizedColor - intermediateNormalizedColor) < 0.0001
        })

        streamBox.yield(
            makeLightDevice(
                level: 20,
                isOn: true,
                colorXY: initialColorXY,
                miredTemperatureW: 345
            )
        )

        #expect(await waitUntil {
            store.selectedPresetKind == intermediatePreset.kind
        })

        try? await Task.sleep(for: .milliseconds(50))

        #expect(await waitUntil {
            store.selectedPresetKind == .pink
                && abs(store.displayedNormalizedColor - initialNormalizedColor) < 0.0001
        })
    }

    @Test
    func missingLevelDescriptorLeavesTheCardUnavailable() async {
        let streamBox = DeviceStreamBox()
        let store = makeStore(streamBox: streamBox)

        streamBox.yield(makePowerOnlyLightDevice(isOn: true))

        #expect(await waitUntil {
            if case .unavailable(deviceId) = store.state {
                return deviceId == self.deviceId
            }
            return false
        })
        #expect(store.isInteractionEnabled == false)
    }

    @Test
    func deinitCancelsTheActiveColorHoldTask() async {
        let streamBox = DeviceStreamBox()
        let sleepRecorder = HoldSleepRecorder()
        var store: SingleLightStore? = SingleLightStore(
            deviceId: deviceId,
            observeLight: .init(
                observeLight: { streamBox.stream }
            ),
            sendCommand: .init(
                sendCommand: { _ in }
            ),
            colorHoldDuration: .seconds(60),
            sleep: { duration in
                try await sleepRecorder.sleep(duration)
            }
        )
        store?.start()

        streamBox.yield(
            makeLightDevice(
                level: 20,
                isOn: true,
                colorXY: initialColorXY,
                miredTemperatureW: 345
            )
        )
        #expect(await waitUntil {
            store?.selectedPresetKind == .pink
        })

        store?.send(.presetWasSelected(committedPreset))

        #expect(await waitUntilAsync {
            await sleepRecorder.starts() == 1
        })

        store = nil

        #expect(await waitUntilAsync {
            await sleepRecorder.cancellations() == 1
        })
    }

    private func makeStore(
        streamBox: DeviceStreamBox,
        commands: RecordedLightGatewayCommands = RecordedLightGatewayCommands(),
        colorHoldDuration: Duration? = nil
    ) -> SingleLightStore {
        let store = SingleLightStore(
            deviceId: deviceId,
            observeLight: .init(
                observeLight: { streamBox.stream }
            ),
            sendCommand: .init(
                sendCommand: { request in
                    await commands.record(request)
                }
            ),
            colorHoldDuration: colorHoldDuration ?? testColorHoldDuration
        )
        store.start()
        return store
    }

    private func makeLightDevice(
        level: Double,
        isOn: Bool,
        colorXY: Int = 1_898_655_292,
        miredTemperatureW: Int? = 345,
        reportsColor: Bool = true
    ) -> Device {
        var data: [String: JSONValue] = [
            "level": .number(level),
            "on": .bool(isOn),
            "minMiredTemperatureW": .number(153),
            "maxMiredTemperatureW": .number(555),
            "colorMode": .string("XY")
        ]

        if reportsColor {
            data["colorXY"] = .number(Double(colorXY))

            if let miredTemperatureW {
                data["miredTemperatureW"] = .number(Double(miredTemperatureW))
            }
        }

        return Device(
            id: deviceId,
            deviceId: deviceId.deviceId,
            endpointId: deviceId.endpointId,
            name: "Living room light",
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
                "miredTemperatureW": .object([
                    "min": .number(153),
                    "max": .number(555)
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

    private func makePowerOnlyLightDevice(isOn: Bool) -> Device {
        Device(
            id: deviceId,
            deviceId: deviceId.deviceId,
            endpointId: deviceId.endpointId,
            name: "TV light",
            usage: "light",
            kind: "light",
            data: [
                "on": .bool(isOn)
            ],
            metadata: [
                "on": .object([
                    "permission": .string("rw")
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

private actor HoldSleepRecorder {
    private var startCount = 0
    private var cancellationCount = 0

    func sleep(_ duration: Duration) async throws {
        startCount += 1

        do {
            try await Task.sleep(for: duration)
        } catch {
            cancellationCount += 1
            throw error
        }
    }

    func starts() -> Int {
        startCount
    }

    func cancellations() -> Int {
        cancellationCount
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
