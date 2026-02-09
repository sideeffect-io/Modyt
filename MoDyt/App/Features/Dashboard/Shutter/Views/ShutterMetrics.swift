import SwiftUI

struct ShutterMetrics {
    let barWidth: CGFloat
    let barSpacing: CGFloat
    let compactHeight: CGFloat
    let expandedHeight: CGFloat
    let cornerRadius: CGFloat
    let padding: CGFloat
    let strokeWidth: CGFloat
    let overlayGap: CGFloat

    var totalWidth: CGFloat {
        barWidth * 5 + barSpacing * 4 + padding * 2
    }

    static let compact = ShutterMetrics(
        barWidth: 26,
        barSpacing: 6,
        compactHeight: 20,
        expandedHeight: 42,
        cornerRadius: 12,
        padding: 8,
        strokeWidth: 3,
        overlayGap: 2
    )

    static let list = ShutterMetrics(
        barWidth: 24,
        barSpacing: 5,
        compactHeight: 16,
        expandedHeight: 36,
        cornerRadius: 10,
        padding: 8,
        strokeWidth: 2.5,
        overlayGap: 1.5
    )

    static let regular = ShutterMetrics(
        barWidth: 20,
        barSpacing: 6,
        compactHeight: 16,
        expandedHeight: 38,
        cornerRadius: 12,
        padding: 10,
        strokeWidth: 2.5,
        overlayGap: 1.5
    )
}
