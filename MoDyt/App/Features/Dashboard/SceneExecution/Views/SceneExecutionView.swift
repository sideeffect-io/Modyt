import SwiftUI

struct SceneExecutionView: View {
    @Environment(\.sceneExecutionStoreFactory) private var sceneExecutionStoreFactory

    let uniqueId: String

    var body: some View {
        WithStoreView(factory: { sceneExecutionStoreFactory.make(uniqueId) }) { store in
            VStack(spacing: 8) {
                SceneExecutionButton(
                    isExecuting: store.state.isExecuting,
                    action: { store.send(.executeTapped) }
                )
                .frame(maxWidth: .infinity, alignment: .center)

                SceneExecutionFeedbackRow(feedback: store.state.feedback)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }
}

private struct SceneExecutionFeedbackRow: View {
    let feedback: SceneExecutionFeedback?

    var body: some View {
        Group {
            if let feedback {
                Label(feedback.title, systemImage: feedback.symbolName)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(feedback.tint)
            } else {
                Text("Tap to run")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .frame(minHeight: 18)
        .accessibilityHidden(feedback == nil)
    }
}

private struct SceneExecutionButton: View {
    let isExecuting: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isExecuting ? Self.activeFill : Self.idleFill)
                    .overlay {
                        Circle()
                            .strokeBorder(
                                Self.borderColor.opacity(isExecuting ? 0.82 : 0.58),
                                lineWidth: isExecuting ? 2.2 : 1.2
                            )
                    }
                    .overlay {
                        Circle()
                            .fill(.white.opacity(isExecuting ? 0.08 : 0.05))
                            .padding(1.2)
                    }
                    .scaleEffect(isExecuting ? 1.08 : 1)
                    .shadow(
                        color: Self.glowColor.opacity(isExecuting ? 0.42 : 0.2),
                        radius: isExecuting ? 11 : 6,
                        x: 0,
                        y: 3
                    )
                    .animation(
                        isExecuting
                        ? .easeInOut(duration: 0.82).repeatForever(autoreverses: true)
                        : .easeOut(duration: 0.2),
                        value: isExecuting
                    )

                Image(systemName: isExecuting ? "arrow.triangle.2.circlepath.circle.fill" : "play.circle.fill")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: isExecuting)
                    .rotationEffect(.degrees(isExecuting ? 360 : 0))
                    .animation(
                        isExecuting
                        ? .linear(duration: 1.1).repeatForever(autoreverses: false)
                        : .easeOut(duration: 0.18),
                        value: isExecuting
                    )
            }
            .frame(width: 84, height: 84)
        }
        .buttonStyle(.plain)
        .disabled(isExecuting)
        .accessibilityLabel(isExecuting ? "Scene execution in progress" : "Execute scene")
        .accessibilityHint(
            isExecuting
            ? "Wait until the scene execution finishes"
            : "Runs this scene on the gateway"
        )
    }

    private static let idleFill = Color(red: 0.17, green: 0.74, blue: 0.57).opacity(0.32)
    private static let activeFill = Color(red: 0.17, green: 0.78, blue: 0.6).opacity(0.42)
    private static let borderColor = Color(red: 0.29, green: 0.92, blue: 0.72)
    private static let glowColor = Color(red: 0.11, green: 0.73, blue: 0.55)
}

private extension SceneExecutionFeedback {
    var title: String {
        switch self {
        case .success:
            return "Execution succeeded"
        case .failure:
            return "Execution failed"
        case .sent:
            return "Execution sent"
        }
    }

    var symbolName: String {
        switch self {
        case .success:
            return "checkmark.seal.fill"
        case .failure:
            return "xmark.octagon.fill"
        case .sent:
            return "clock.arrow.circlepath"
        }
    }

    var tint: Color {
        switch self {
        case .success:
            return .green
        case .failure:
            return .red
        case .sent:
            return AppColors.ember
        }
    }
}
