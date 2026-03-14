import Foundation

enum DeviceGroup: String, CaseIterable, Sendable {
    case shutter
    case window
    case door
    case garage
    case gate
    case light
    case energy
    case smoke
    case boiler
    case alarm
    case weather
    case water
    case thermo
    case other

    var title: String {
        switch self {
        case .shutter: return "Shutters"
        case .window: return "Windows"
        case .door: return "Doors"
        case .garage: return "Garage"
        case .gate: return "Gates"
        case .light: return "Lights"
        case .energy: return "Energy"
        case .smoke: return "Smoke"
        case .boiler: return "Boilers"
        case .alarm: return "Alarm"
        case .weather: return "Weather"
        case .water: return "Water"
        case .thermo: return "Thermo"
        case .other: return "Other"
        }
    }

    var symbolName: String {
        switch self {
        case .shutter: return "window.horizontal"
        case .window: return "rectangle.portrait"
        case .door: return "door.left.hand.open"
        case .garage: return "car"
        case .gate: return "square.split.2x2"
        case .light: return "lightbulb"
        case .energy: return "bolt"
        case .smoke: return "smoke"
        case .boiler: return "thermometer"
        case .alarm: return "shield.lefthalf.filled"
        case .weather: return "cloud.sun"
        case .water: return "drop"
        case .thermo: return "thermometer.medium"
        case .other: return "square.dashed"
        }
    }

    static func from(usage: String) -> DeviceGroup {
        switch usage {
        case "shutter", "klineShutter", "awning", "swingShutter":
            return .shutter
        case "window", "windowFrench", "windowSliding", "klineWindowFrench", "klineWindowSliding":
            return .window
        case "belmDoor", "klineDoor":
            return .door
        case "garage_door":
            return .garage
        case "gate":
            return .gate
        case "light":
            return .light
        case "conso":
            return .energy
        case "sensorDFR":
            return .smoke
        case "boiler", "sh_hvac", "electric", "aeraulic", "re2020ControlBoiler":
            return .boiler
        case "alarm":
            return .alarm
        case "weather", "sunlight", "sensorSun", "sensorSunlight", "irradiance":
            return .weather
        case "sensorDF":
            return .water
        case "sensorThermo":
            return .thermo
        default:
            return .other
        }
    }
}

struct DeviceControlDescriptor: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case toggle
        case slider
    }

    let kind: Kind
    let key: String
    let isOn: Bool
    let value: Double
    let range: ClosedRange<Double>
}

struct DrivingLightColorDescriptor: Sendable, Equatable {
    let key: String
    let modeKey: String?
    let modeValue: String?
    let temperatureKey: String?
    let value: Double
    let range: ClosedRange<Double>

    var normalizedValue: Double {
        normalizedValue(forRawValue: Int(value.rounded()))
    }

    func payload(forNormalizedValue normalizedValue: Double) -> DrivingLightColorPayload {
        switch encoding {
        case .packedXY:
            if let calibration {
                let calibratedPayload = calibration.payload(for: normalizedValue)
                return DrivingLightColorPayload(
                    rawValue: calibratedPayload.packedXY,
                    miredTemperatureW: temperatureKey == nil ? nil : calibratedPayload.miredTemperatureW
                )
            }
            return DrivingLightColorPayload(
                rawValue: packedXYRawValue(forNormalizedValue: normalizedValue),
                miredTemperatureW: nil
            )
        case .hueDegrees:
            return DrivingLightColorPayload(
                rawValue: linearRawValue(forNormalizedValue: normalizedValue, in: 0...360),
                miredTemperatureW: nil
            )
        case .linear:
            return DrivingLightColorPayload(
                rawValue: linearRawValue(forNormalizedValue: normalizedValue, in: range),
                miredTemperatureW: nil
            )
        }
    }

    func rawValue(forNormalizedValue normalizedValue: Double) -> Int {
        payload(forNormalizedValue: normalizedValue).rawValue
    }

    func normalizedValue(forRawValue rawValue: Int) -> Double {
        switch encoding {
        case .packedXY:
            return normalizedPackedXYValue(forRawValue: rawValue)
        case .hueDegrees:
            return linearNormalizedValue(forRawValue: rawValue, in: 0...360)
        case .linear:
            return linearNormalizedValue(forRawValue: rawValue, in: range)
        }
    }

    static let packedXYCalibration = LightColorCalibration.defaultProfile

    private enum Encoding {
        case packedXY
        case hueDegrees
        case linear
    }

    private var encoding: Encoding {
        let normalizedKey = key.lowercased()
        if normalizedKey == "colorxy" {
            return .packedXY
        }
        if normalizedKey.contains("hue") {
            return .hueDegrees
        }
        return .linear
    }

    private func linearRawValue(
        forNormalizedValue normalizedValue: Double,
        in range: ClosedRange<Double>
    ) -> Int {
        let clampedNormalizedValue = min(max(normalizedValue, 0), 1)
        let rawValue = range.lowerBound + ((range.upperBound - range.lowerBound) * clampedNormalizedValue)
        return Int(rawValue.rounded())
    }

    private func linearNormalizedValue(
        forRawValue rawValue: Int,
        in range: ClosedRange<Double>
    ) -> Double {
        let clampedValue = min(max(Double(rawValue), range.lowerBound), range.upperBound)
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(max((clampedValue - range.lowerBound) / span, 0), 1)
    }

    private func packedXYRawValue(forNormalizedValue normalizedValue: Double) -> Int {
        let clampedNormalizedValue = min(max(normalizedValue, 0), 1)
        let rgb = Self.rgbComponents(forHue: clampedNormalizedValue)
        let xy = Self.xyCoordinates(for: rgb)
        let xWord = Self.packedXYWord(for: xy.x)
        let yWord = Self.packedXYWord(for: xy.y)
        let packedValue = (yWord << 16) | xWord
        return Int(packedValue)
    }

    private func normalizedPackedXYValue(forRawValue rawValue: Int) -> Double {
        if let calibration {
            return calibration.normalizedValue(forPackedXY: rawValue)
        }

        let xy = Self.xyCoordinates(forPackedValue: rawValue)
        let rgb = Self.rgbComponents(forXY: xy.x, y: xy.y)
        return Self.normalizedHue(for: rgb) ?? DrivingLightControlDescriptor.defaultNormalizedColor
    }

    private var calibration: LightColorCalibration? {
        guard encoding == .packedXY else { return nil }
        return Self.packedXYCalibration
    }

    private static func packedXYWord(for coordinate: Double) -> UInt32 {
        let clampedCoordinate = min(max(coordinate, 0), 1)
        let scaledWord = UInt32((clampedCoordinate * packedXYComponentDenominator).rounded())
        return min(scaledWord, packedXYComponentWordMax)
    }

    private static func xyCoordinates(forPackedValue rawValue: Int) -> (x: Double, y: Double) {
        let packedValue = UInt32(clamping: rawValue)

        // Captured Tydom `colorXY` values decode plausibly when x is stored in the low word.
        let xWord = Double(packedValue & 0xFFFF)
        let yWord = Double((packedValue >> 16) & 0xFFFF)

        return (
            x: min(max(xWord / packedXYComponentDenominator, 0), 1),
            y: min(max(yWord / packedXYComponentDenominator, 0), 1)
        )
    }

    private static func rgbComponents(forHue normalizedHue: Double) -> (red: Double, green: Double, blue: Double) {
        let hue = normalizedHue * 6
        let segment = Int(floor(hue)) % 6
        let progress = hue - floor(hue)
        let q = 1 - progress
        let t = progress

        switch segment {
        case 0:
            return (1, t, 0)
        case 1:
            return (q, 1, 0)
        case 2:
            return (0, 1, t)
        case 3:
            return (0, q, 1)
        case 4:
            return (t, 0, 1)
        default:
            return (1, 0, q)
        }
    }

    private static func xyCoordinates(for rgb: (red: Double, green: Double, blue: Double)) -> (x: Double, y: Double) {
        let red = linearizedComponent(rgb.red)
        let green = linearizedComponent(rgb.green)
        let blue = linearizedComponent(rgb.blue)

        let xComponent = (red * 0.41239079926595934) + (green * 0.357584339383878) + (blue * 0.1804807884018343)
        let yComponent = (red * 0.21263900587151027) + (green * 0.715168678767756) + (blue * 0.07219231536073371)
        let zComponent = (red * 0.01933081871559182) + (green * 0.11919477979462598) + (blue * 0.9505321522496607)
        let total = xComponent + yComponent + zComponent

        guard total > 0.00001 else {
            return (0.3127, 0.3290)
        }

        return (
            x: xComponent / total,
            y: yComponent / total
        )
    }

    private static func rgbComponents(forXY x: Double, y: Double) -> (red: Double, green: Double, blue: Double) {
        guard y > 0.00001 else { return (1, 1, 1) }

        let luminance = 1.0
        let xComponent = (luminance / y) * x
        let zComponent = (luminance / y) * (1 - x - y)

        var red = (xComponent * 3.240969941904521) - (luminance * 1.537383177570093) - (zComponent * 0.498610760293)
        var green = (-xComponent * 0.96924363628087) + (luminance * 1.87596750150772) + (zComponent * 0.041555057407175)
        var blue = (xComponent * 0.055630079696993) - (luminance * 0.20397695888897) + (zComponent * 1.056971514242878)

        red = max(red, 0)
        green = max(green, 0)
        blue = max(blue, 0)

        let scale = max(red, green, blue, 1)
        return (
            red: gammaCorrectedComponent(red / scale),
            green: gammaCorrectedComponent(green / scale),
            blue: gammaCorrectedComponent(blue / scale)
        )
    }

    private static func normalizedHue(for rgb: (red: Double, green: Double, blue: Double)) -> Double? {
        let maximum = max(rgb.red, rgb.green, rgb.blue)
        let minimum = min(rgb.red, rgb.green, rgb.blue)
        let delta = maximum - minimum

        guard delta > 0.00001 else { return nil }

        let hue: Double
        switch maximum {
        case rgb.red:
            hue = ((rgb.green - rgb.blue) / delta).truncatingRemainder(dividingBy: 6)
        case rgb.green:
            hue = ((rgb.blue - rgb.red) / delta) + 2
        default:
            hue = ((rgb.red - rgb.green) / delta) + 4
        }

        let normalizedHue = hue / 6
        return normalizedHue >= 0 ? normalizedHue : normalizedHue + 1
    }

    private static func linearizedComponent(_ component: Double) -> Double {
        if component <= 0.04045 {
            return component / 12.92
        }
        return pow((component + 0.055) / 1.055, 2.4)
    }

    private static func gammaCorrectedComponent(_ component: Double) -> Double {
        if component <= 0.0031308 {
            return 12.92 * component
        }
        return (1.055 * pow(component, 1 / 2.4)) - 0.055
    }

    private static let packedXYComponentDenominator = 65_536.0
    private static let packedXYComponentWordMax = UInt32(UInt16.max)
}

struct DrivingLightColorPayload: Sendable, Equatable {
    let rawValue: Int
    let miredTemperatureW: Int?
}

struct DrivingLightControlDescriptor: Sendable, Equatable {
    let powerKey: String?
    let levelKey: String?
    let isOn: Bool
    let level: Double
    let range: ClosedRange<Double>
    let color: DrivingLightColorDescriptor?

    var normalizedLevel: Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return isOn ? 1 : 0 }
        let normalized = (level - range.lowerBound) / span
        return min(max(normalized, 0), 1)
    }

    var normalizedColor: Double {
        color?.normalizedValue ?? Self.defaultNormalizedColor
    }

    var percentage: Int {
        Int((normalizedLevel * 100).rounded())
    }

    var minimumLevel: Int {
        Int(range.lowerBound.rounded())
    }

    var maximumLevel: Int {
        Int(range.upperBound.rounded())
    }

    func rawLevel(forNormalizedLevel normalizedLevel: Double) -> Int {
        let clampedNormalizedLevel = min(max(normalizedLevel, 0), 1)
        let rawLevel = range.lowerBound + ((range.upperBound - range.lowerBound) * clampedNormalizedLevel)
        return Int(rawLevel.rounded())
    }

    func normalizedLevel(forRawLevel rawLevel: Int) -> Double {
        let clampedLevel = min(max(Double(rawLevel), range.lowerBound), range.upperBound)
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return clampedLevel > range.lowerBound ? 1 : 0 }
        return min(max((clampedLevel - range.lowerBound) / span, 0), 1)
    }

    func isLit(level rawLevel: Int) -> Bool {
        Double(rawLevel) > range.lowerBound
    }

    static let defaultNormalizedColor = 0.12
}
