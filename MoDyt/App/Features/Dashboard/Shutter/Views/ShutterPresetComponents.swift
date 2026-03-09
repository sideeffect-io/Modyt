import SwiftUI

struct ShutterPresetButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct ShutterPresetIcon: View {
    let openPercentage: Int

    private var closedRatio: CGFloat {
        let clampedOpen = CGFloat(min(max(openPercentage, 0), 100))
        return 1 - (clampedOpen / 100)
    }

    var body: some View {
        GeometryReader { proxy in
            let innerInset: CGFloat = 3
            let innerWidth = max(proxy.size.width - (innerInset * 2), 0)
            let innerHeight = max(proxy.size.height - (innerInset * 2), 0)
            let curtainHeight = innerHeight * closedRatio

            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.05))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.primary.opacity(0.8), lineWidth: 1.25)
                }
                .overlay(alignment: .top) {
                    if curtainHeight > 0.5 {
                        ZStack(alignment: .top) {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.primary.opacity(0.08))

                            let linePitch: CGFloat = 4
                            let lineCount = max(Int((curtainHeight / linePitch).rounded(.up)), 1)

                            VStack(spacing: max(linePitch - 1.2, 1)) {
                                ForEach(0..<lineCount, id: \.self) { _ in
                                    Rectangle()
                                        .fill(Color.primary.opacity(0.9))
                                        .frame(height: 1.2)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 1)
                        }
                        .frame(width: innerWidth, height: curtainHeight, alignment: .top)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .padding(.top, innerInset)
                    }
                }
        }
    }
}
