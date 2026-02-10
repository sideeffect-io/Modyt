import SwiftUI
import DeltaDoreClient

struct ShutterView: View {
    @Environment(\.shutterStoreFactory) private var shutterStoreFactory
    @Environment(\.colorScheme) private var colorScheme
    
    let uniqueId: String
    let layout: ShutterControlLayout
    
    var body: some View {
        WithStoreView(factory: { shutterStoreFactory.make(uniqueId) }) { store in
            shutterContent(store: store)
        }
    }
    
    @ViewBuilder
    private func shutterContent(store: ShutterStore) -> some View {
        let metrics = layout.metrics
        
        if case .regular = layout {
            regularControl(metrics: metrics, store: store)
                .padding(.vertical, metrics.padding)
                .frame(maxWidth: .infinity)
                .glassCard(cornerRadius: containerCornerRadius, interactive: true)
        } else {
            horizontalControl(metrics: metrics, store: store)
                .padding(.vertical, metrics.padding)
                .frame(maxWidth: .infinity)
                .glassCard(cornerRadius: containerCornerRadius, interactive: true)
        }
    }
    
    private func regularControl(metrics: ShutterMetrics, store: ShutterStore) -> some View {
        VStack(spacing: controlSpacing) {
            regularPills(metrics: metrics, store: store)
            horizontalIcons(metrics: metrics)
        }
    }
    
    private func regularPills(metrics: ShutterMetrics, store: ShutterStore) -> some View {
        HStack(alignment: .bottom, spacing: metrics.barSpacing) {
            ForEach(ShutterStep.allCases) { step in
                Button {
                    store.select(step)
                } label: {
                    ShutterPill(
                        step: step,
                        isTarget: step == store.effectiveTargetStep,
                        isActual: step == store.actualStep,
                        isInFlight: store.isInFlight,
                        metrics: metrics
                    )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(step.accessibilityLabel)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, metrics.padding)
    }
    
    private func horizontalControl(metrics: ShutterMetrics, store: ShutterStore) -> some View {
        VStack(spacing: controlSpacing) {
            horizontalPills(metrics: metrics, store: store)
            horizontalIcons(metrics: metrics)
        }
    }
    
    private func horizontalPills(metrics: ShutterMetrics, store: ShutterStore) -> some View {
        HStack(alignment: .bottom, spacing: metrics.barSpacing) {
            ForEach(ShutterStep.allCases) { step in
                Button {
                    store.select(step)
                } label: {
                    ShutterPill(
                        step: step,
                        isTarget: step == store.effectiveTargetStep,
                        isActual: step == store.actualStep,
                        isInFlight: store.isInFlight,
                        metrics: metrics
                    )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(step.accessibilityLabel)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, metrics.padding)
    }
    
    private func horizontalIcons(metrics: ShutterMetrics) -> some View {
        HStack(spacing: metrics.barSpacing) {
            ForEach(ShutterStep.allCases) { step in
                iconView(for: step)
                    .frame(maxWidth: .infinity)
            }
        }
        .font(.system(size: iconSize, weight: .semibold))
        .foregroundStyle(colorScheme == .dark ? .white.opacity(0.7) : .secondary)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, metrics.padding)
    }
    
    private var containerCornerRadius: CGFloat {
        switch layout {
        case .list:
            return 14
        case .compact, .regular:
            return 18
        }
    }
    
    private var controlSpacing: CGFloat {
        switch layout {
        case .list:
            return 8
        case .compact, .regular:
            return 10
        }
    }
    
    private var iconSize: CGFloat {
        switch layout {
        case .list:
            return 12
        case .compact, .regular:
            return 14
        }
    }
    
    @ViewBuilder
    private func iconView(for step: ShutterStep) -> some View {
        switch step {
        case .open:
            Image(systemName: "sun.max")
        case .half:
            Image(systemName: "circle.bottomhalf.filled")
        case .closed:
            Image(systemName: "moon")
        case .quarter, .threeQuarter:
            Color.clear
        }
    }
}
