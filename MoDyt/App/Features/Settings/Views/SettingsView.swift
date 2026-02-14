import SwiftUI

struct SettingsView: View {
    @Environment(\.settingsStoreFactory) private var settingsStoreFactory
    let onDidDisconnect: @MainActor () -> Void

    var body: some View {
        WithStoreView(factory: settingsStoreFactory.make) { store in
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Connection")
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                    Text("Disconnect to switch account or re-run setup.")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    store.send(.disconnectTapped)
                } label: {
                    HStack {
                        if store.state.isDisconnecting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "power")
                        }
                        Text(store.state.isDisconnecting ? "Disconnecting..." : "Disconnect")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.state.isDisconnecting)

                if let errorMessage = store.state.errorMessage {
                    Text(errorMessage)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(20)
            .glassCard(cornerRadius: 24)
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .onChange(of: store.state.didDisconnect) { _, didDisconnect in
                guard didDisconnect else { return }
                onDidDisconnect()
            }
        }
    }
}
