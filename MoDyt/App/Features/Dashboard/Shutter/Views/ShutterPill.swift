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
                ? Color(red: 0.56, green: 0.57, blue: 0.6)
                : Color(red: 0.45, green: 0.46, blue: 0.49)
            let bottom = isTarget
                ? Color(red: 0.47, green: 0.48, blue: 0.51)
                : Color(red: 0.37, green: 0.38, blue: 0.41)
            colors = [top, bottom]
        } else {
            colors = [
                Color(red: 0.72, green: 0.73, blue: 0.75).opacity(isTarget ? 1.0 : 0.88),
                Color(red: 0.62, green: 0.63, blue: 0.66).opacity(isTarget ? 1.0 : 0.88)
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
            .animation(.easeInOut(duration: 0.24), value: isActual)
            .animation(.easeInOut(duration: 0.24), value: isInFlight)
            .frame(minWidth: metrics.barWidth, maxWidth: .infinity, minHeight: metrics.expandedHeight, alignment: .bottom)
            .contentShape(.rect)
    }
}
