import Foundation

struct LightColorPreset: Sendable, Equatable, Identifiable {
    enum Kind: String, CaseIterable, Sendable {
        case red = "Red"
        case pink = "Pink"
        case violet = "Violet"
        case blue = "Blue"
        case cyan = "Cyan"
        case green = "Green"
        case yellow = "Yellow"
        case orange = "Orange"
    }

    let kind: Kind
    let normalizedValue: Double
    let packedXY: Int
    let miredTemperatureW: Int?
    let displayRGB: LightColorCalibration.RGBComponents

    var id: Kind { kind }
    var title: String { kind.rawValue }
}

struct LightColorCalibration: Sendable {
    struct RGBComponents: Sendable, Equatable {
        let red: Double
        let green: Double
        let blue: Double
    }

    struct Point: Sendable, Equatable {
        let normalizedValue: Double
        let packedXY: Int
        let miredTemperatureW: Int?
        let displayRGB: RGBComponents
    }

    struct Payload: Sendable, Equatable {
        let packedXY: Int
        let miredTemperatureW: Int?
    }

    let points: [Point]

    init(points: [Point]) {
        self.points = points.sorted { $0.normalizedValue < $1.normalizedValue }
    }

    var presets: [LightColorPreset] {
        Self.presetDefinitions.compactMap { definition in
            guard let point = points.min(by: {
                abs($0.normalizedValue - definition.normalizedValue) < abs($1.normalizedValue - definition.normalizedValue)
            }) else {
                return nil
            }

            return LightColorPreset(
                kind: definition.kind,
                normalizedValue: definition.normalizedValue,
                packedXY: point.packedXY,
                miredTemperatureW: point.miredTemperatureW,
                displayRGB: point.displayRGB
            )
        }
    }

    func payload(for normalizedValue: Double) -> Payload {
        let clampedNormalizedValue = min(max(normalizedValue, 0), 1)

        if let snappedPoint = snappedPoint(for: clampedNormalizedValue) {
            return Payload(
                packedXY: snappedPoint.packedXY,
                miredTemperatureW: snappedPoint.miredTemperatureW
            )
        }

        let segment = segment(for: clampedNormalizedValue)
        let lowerXY = Self.xyCoordinates(forPackedValue: segment.lower.packedXY)
        let upperXY = Self.xyCoordinates(forPackedValue: segment.upper.packedXY)

        let payloadTemperature: Int?
        switch (segment.lower.miredTemperatureW, segment.upper.miredTemperatureW) {
        case let (.some(lower), .some(upper)):
            payloadTemperature = Int(Self.interpolate(Double(lower), Double(upper), factor: segment.factor).rounded())
        default:
            payloadTemperature = nil
        }

        return Payload(
            packedXY: Self.packedXYValue(
                x: Self.interpolate(lowerXY.x, upperXY.x, factor: segment.factor),
                y: Self.interpolate(lowerXY.y, upperXY.y, factor: segment.factor)
            ),
            miredTemperatureW: payloadTemperature
        )
    }

    func nearestPreset(for normalizedValue: Double) -> LightColorPreset? {
        let clampedNormalizedValue = normalizedValue.truncatingRemainder(dividingBy: 1)
        let wrappedNormalizedValue = clampedNormalizedValue >= 0 ? clampedNormalizedValue : clampedNormalizedValue + 1

        return presets.min { lhs, rhs in
            Self.circularDistance(lhs.normalizedValue, wrappedNormalizedValue)
                < Self.circularDistance(rhs.normalizedValue, wrappedNormalizedValue)
        }
    }

    func nearestPreset(forPackedXY packedXY: Int) -> LightColorPreset? {
        let target = Self.xyCoordinates(forPackedValue: packedXY)

        return presets.min { lhs, rhs in
            Self.distanceSquared(
                from: target,
                to: Self.xyCoordinates(forPackedValue: lhs.packedXY)
            ) < Self.distanceSquared(
                from: target,
                to: Self.xyCoordinates(forPackedValue: rhs.packedXY)
            )
        }
    }

    func normalizedValue(forPackedXY packedXY: Int) -> Double {
        if let exactMatch = points.last(where: { $0.packedXY == packedXY }) {
            return exactMatch.normalizedValue
        }

        let target = Self.xyCoordinates(forPackedValue: packedXY)
        guard points.count > 1 else { return points.first?.normalizedValue ?? 0 }

        var closestNormalizedValue = points[0].normalizedValue
        var smallestDistance = Double.greatestFiniteMagnitude

        for index in 0..<(points.count - 1) {
            let lower = points[index]
            let upper = points[index + 1]
            let projection = Self.project(
                point: target,
                ontoSegmentFrom: Self.xyCoordinates(forPackedValue: lower.packedXY),
                to: Self.xyCoordinates(forPackedValue: upper.packedXY)
            )

            if projection.distanceSquared < smallestDistance {
                smallestDistance = projection.distanceSquared
                closestNormalizedValue = Self.interpolate(
                    lower.normalizedValue,
                    upper.normalizedValue,
                    factor: projection.factor
                )
            }
        }

        return closestNormalizedValue
    }

    func displayRGB(for normalizedValue: Double) -> RGBComponents {
        let clampedNormalizedValue = min(max(normalizedValue, 0), 1)

        if let snappedPoint = snappedPoint(for: clampedNormalizedValue) {
            return snappedPoint.displayRGB
        }

        let segment = segment(for: clampedNormalizedValue)
        return RGBComponents(
            red: Self.interpolate(segment.lower.displayRGB.red, segment.upper.displayRGB.red, factor: segment.factor),
            green: Self.interpolate(segment.lower.displayRGB.green, segment.upper.displayRGB.green, factor: segment.factor),
            blue: Self.interpolate(segment.lower.displayRGB.blue, segment.upper.displayRGB.blue, factor: segment.factor)
        )
    }

    private func snappedPoint(for normalizedValue: Double) -> Point? {
        let nearestPoint = points.min { lhs, rhs in
            abs(lhs.normalizedValue - normalizedValue) < abs(rhs.normalizedValue - normalizedValue)
        }

        guard let nearestPoint,
              abs(nearestPoint.normalizedValue - normalizedValue) <= Self.snapThreshold else {
            return nil
        }

        return nearestPoint
    }

    private func segment(for normalizedValue: Double) -> (lower: Point, upper: Point, factor: Double) {
        guard points.count > 1 else {
            let point = points.first ?? Self.defaultProfile.points[0]
            return (point, point, 0)
        }

        for index in 0..<(points.count - 1) {
            let lower = points[index]
            let upper = points[index + 1]
            if normalizedValue <= upper.normalizedValue {
                let span = max(upper.normalizedValue - lower.normalizedValue, .leastNonzeroMagnitude)
                let factor = min(max((normalizedValue - lower.normalizedValue) / span, 0), 1)
                return (lower, upper, factor)
            }
        }

        let lower = points[points.count - 2]
        let upper = points[points.count - 1]
        return (lower, upper, 1)
    }

    private static func interpolate(_ lower: Double, _ upper: Double, factor: Double) -> Double {
        lower + ((upper - lower) * factor)
    }

    private static func circularDistance(_ lhs: Double, _ rhs: Double) -> Double {
        let delta = abs(lhs - rhs)
        return min(delta, 1 - delta)
    }

    private static func distanceSquared(
        from lhs: (x: Double, y: Double),
        to rhs: (x: Double, y: Double)
    ) -> Double {
        pow(lhs.x - rhs.x, 2) + pow(lhs.y - rhs.y, 2)
    }

    private static func project(
        point: (x: Double, y: Double),
        ontoSegmentFrom start: (x: Double, y: Double),
        to end: (x: Double, y: Double)
    ) -> (factor: Double, distanceSquared: Double) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = (dx * dx) + (dy * dy)

        guard lengthSquared > 0 else {
            let distanceSquared = pow(point.x - start.x, 2) + pow(point.y - start.y, 2)
            return (0, distanceSquared)
        }

        let rawFactor = (((point.x - start.x) * dx) + ((point.y - start.y) * dy)) / lengthSquared
        let factor = min(max(rawFactor, 0), 1)
        let projectedPoint = (
            x: start.x + (dx * factor),
            y: start.y + (dy * factor)
        )
        let distanceSquared = pow(point.x - projectedPoint.x, 2) + pow(point.y - projectedPoint.y, 2)
        return (factor, distanceSquared)
    }

    private static func xyCoordinates(forPackedValue rawValue: Int) -> (x: Double, y: Double) {
        let packedValue = UInt32(clamping: rawValue)
        let xWord = Double(packedValue & 0xFFFF)
        let yWord = Double((packedValue >> 16) & 0xFFFF)

        return (
            x: min(max(xWord / packedXYComponentDenominator, 0), 1),
            y: min(max(yWord / packedXYComponentDenominator, 0), 1)
        )
    }

    private static func packedXYValue(x: Double, y: Double) -> Int {
        let xWord = packedXYWord(for: x)
        let yWord = packedXYWord(for: y)
        return Int((yWord << 16) | xWord)
    }

    private static func packedXYWord(for coordinate: Double) -> UInt32 {
        let clampedCoordinate = min(max(coordinate, 0), 1)
        let scaledWord = UInt32((clampedCoordinate * packedXYComponentDenominator).rounded())
        return min(scaledWord, packedXYComponentWordMax)
    }

    private static let packedXYComponentDenominator = 65_536.0
    private static let packedXYComponentWordMax = UInt32(UInt16.max)
    private static let snapThreshold = 0.03
    private static let presetDefinitions: [(kind: LightColorPreset.Kind, normalizedValue: Double)] = [
        (.red, 1.0),
        (.pink, 0.88),
        (.violet, 0.76),
        (.blue, 0.60),
        (.cyan, 0.46),
        (.green, 0.32),
        (.yellow, 0.18),
        (.orange, 0.08),
    ]
}

extension LightColorCalibration {
    static let defaultProfile = Self(points: [
        Point(
            normalizedValue: 0.00,
            packedXY: 3_002_682_482,
            miredTemperatureW: 555,
            displayRGB: .init(red: 0.98, green: 0.22, blue: 0.18)
        ),
        Point(
            normalizedValue: 0.08,
            packedXY: 2_385_996_822,
            miredTemperatureW: 555,
            displayRGB: .init(red: 1.00, green: 0.58, blue: 0.18)
        ),
        Point(
            normalizedValue: 0.18,
            packedXY: 1_921_155_983,
            miredTemperatureW: 353,
            displayRGB: .init(red: 0.98, green: 0.84, blue: 0.16)
        ),
        Point(
            normalizedValue: 0.32,
            packedXY: 740_343_536,
            miredTemperatureW: 153,
            displayRGB: .init(red: 0.35, green: 0.83, blue: 0.31)
        ),
        Point(
            normalizedValue: 0.46,
            packedXY: 650_139_661,
            miredTemperatureW: 153,
            displayRGB: .init(red: 0.20, green: 0.88, blue: 0.95)
        ),
        Point(
            normalizedValue: 0.60,
            packedXY: 585_108_043,
            miredTemperatureW: 153,
            displayRGB: .init(red: 0.24, green: 0.47, blue: 1.00)
        ),
        Point(
            normalizedValue: 0.76,
            packedXY: 1_081_743_330,
            miredTemperatureW: 153,
            displayRGB: .init(red: 0.65, green: 0.40, blue: 1.00)
        ),
        Point(
            normalizedValue: 0.88,
            packedXY: 1_898_655_292,
            miredTemperatureW: 345,
            displayRGB: .init(red: 1.00, green: 0.44, blue: 0.71)
        ),
        Point(
            normalizedValue: 1.00,
            packedXY: 3_002_682_482,
            miredTemperatureW: 555,
            displayRGB: .init(red: 0.98, green: 0.22, blue: 0.18)
        ),
    ])
}
