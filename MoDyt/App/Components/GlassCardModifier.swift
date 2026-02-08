import SwiftUI

extension View {
    @ViewBuilder
    func glassCard(cornerRadius: CGFloat = 20, interactive: Bool = true) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            let base = interactive ? Glass.regular.interactive() : Glass.regular
            self.glassEffect(base, in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}
