import SwiftUI

enum ShutterPresetLayoutStyle {
    case regularSingleRow
    case compactSingleRow

    static func make(for controlWidth: CGFloat) -> Self {
        let minimumWidth = minimumRegularControlWidth
        if controlWidth >= minimumWidth {
            return .regularSingleRow
        }
        return .compactSingleRow
    }

    var containerHorizontalPadding: CGFloat {
        switch self {
        case .regularSingleRow:
            return 10
        case .compactSingleRow:
            return 6
        }
    }

    var containerVerticalPadding: CGFloat {
        switch self {
        case .regularSingleRow:
            return 10
        case .compactSingleRow:
            return 8
        }
    }

    var sectionSpacing: CGFloat {
        switch self {
        case .regularSingleRow:
            return 10
        case .compactSingleRow:
            return 8
        }
    }

    var presetHorizontalSpacing: CGFloat {
        switch self {
        case .regularSingleRow:
            return 8
        case .compactSingleRow:
            return 3
        }
    }

    var buttonHeight: CGFloat {
        switch self {
        case .regularSingleRow:
            return 44
        case .compactSingleRow:
            return 38
        }
    }

    var iconHorizontalPadding: CGFloat {
        switch self {
        case .regularSingleRow:
            return 4
        case .compactSingleRow:
            return 2
        }
    }

    var iconVerticalPadding: CGFloat {
        switch self {
        case .regularSingleRow:
            return 5
        case .compactSingleRow:
            return 4
        }
    }

    var badgeHorizontalPadding: CGFloat {
        switch self {
        case .regularSingleRow:
            return 10
        case .compactSingleRow:
            return 8
        }
    }

    var badgeVerticalPadding: CGFloat {
        switch self {
        case .regularSingleRow:
            return 6
        case .compactSingleRow:
            return 5
        }
    }

    var badgeFont: Font {
        switch self {
        case .regularSingleRow:
            return .system(.caption2, design: .rounded).weight(.semibold)
        case .compactSingleRow:
            return .system(size: 11, weight: .semibold, design: .rounded)
        }
    }

    private static let minimumRegularPresetWidth: CGFloat = 24
    private static let minimumRegularControlWidth =
        (minimumRegularPresetWidth * CGFloat(ShutterPreset.allCases.count))
        + (8 * CGFloat(max(ShutterPreset.allCases.count - 1, 0)))
        + (10 * 2)
}

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
