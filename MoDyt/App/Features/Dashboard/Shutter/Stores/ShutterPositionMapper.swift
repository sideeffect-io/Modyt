import Foundation

enum ShutterPositionMapper {
    static func gaugePosition(from position: Int) -> Int {
        invert(position)
    }

    private static func invert(_ value: Int) -> Int {
        100 - clamp(value)
    }

    private static func clamp(_ value: Int) -> Int {
        min(max(value, 0), 100)
    }
}
