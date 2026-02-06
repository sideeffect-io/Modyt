import SwiftUI

struct ShutterActualOverlay: View {
    let isVisible: Bool
    let isPulsing: Bool
    let metrics: ShutterMetrics

    @State private var pulseOn = false

    private var pulseOpacity: Double {
        isPulsing ? (pulseOn ? 0.2 : 1.0) : 1.0
    }

    var body: some View {
        RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
            .inset(by: -(metrics.overlayGap + metrics.strokeWidth / 2))
            .stroke(.blue, lineWidth: metrics.strokeWidth)
            .shadow(color: .blue.opacity(isPulsing ? 0.6 : 0.4), radius: isPulsing ? 8 : 6)
            .opacity(isVisible ? 1 : 0)
            .animation(.easeInOut(duration: 0.24), value: isVisible)
            .opacity(pulseOpacity)
            .onAppear { updatePulse(isPulsing) }
            .onChange(of: isPulsing) { _, newValue in
                updatePulse(newValue)
            }
    }

    private func updatePulse(_ active: Bool) {
        if active {
            pulseOn = false
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulseOn = true
            }
        } else {
            withAnimation(.easeOut(duration: 0.2)) {
                pulseOn = false
            }
        }
    }
}
