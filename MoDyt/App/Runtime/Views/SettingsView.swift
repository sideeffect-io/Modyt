import SwiftUI

struct SettingsView: View {
    @Bindable var store: RuntimeStore

    var body: some View {
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
                    Image(systemName: "power")
                    Text("Disconnect")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(20)
        .glassCard(cornerRadius: 24)
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
    }
}
