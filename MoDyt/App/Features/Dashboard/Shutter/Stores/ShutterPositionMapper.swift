import Foundation

enum ShutterPositionMapper {
    static let maximumGaugePosition = 105

    static func gaugePosition(from position: Int) -> Int {
        clamp(maximumGaugePosition - position)
    }

    private static func clamp(_ value: Int) -> Int {
        min(max(value, 0), maximumGaugePosition)
    }
}
