import SwiftUI

struct ShutterPill: View {
    let step: ShutterStep
    let isTarget: Bool
    let isActual: Bool
    let isInFlight: Bool
    let metrics: ShutterMetrics

    @Environment(\.colorScheme) private var colorScheme

    private var pillGradient: LinearGradient {
        let colors: [Color]
        if colorScheme == .dark {
            let top = isTarget
                ? Color(red: 0.36, green: 0.37, blue: 0.4)
                : Color(red: 0.3, green: 0.31, blue: 0.33)
            let bottom = isTarget
                ? Color(red: 0.28, green: 0.29, blue: 0.32)
                : Color(red: 0.23, green: 0.24, blue: 0.26)
            colors = [top, bottom]
        } else {
            colors = [
                .black.opacity(isTarget ? 0.9 : 0.82),
                .black.opacity(isTarget ? 0.7 : 0.64)
            ]
        }
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }

    var body: some View {
        RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
            .fill(pillGradient)
            .frame(
                height: isTarget ? metrics.expandedHeight : metrics.compactHeight,
                alignment: .bottom
            )
            .overlay {
                ShutterActualOverlay(
                    isVisible: isActual,
                    isPulsing: isInFlight && isActual,
                    metrics: metrics
                )
            }
            .shadow(color: .black.opacity(isTarget ? 0.35 : 0.2), radius: 6, x: 0, y: 4)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isTarget)
            .frame(minWidth: metrics.barWidth, maxWidth: .infinity, minHeight: metrics.expandedHeight, alignment: .bottom)
            .contentShape(.rect)
    }
}
