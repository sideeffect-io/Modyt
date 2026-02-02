import SwiftUI
import DeltaDoreClient

struct LoginView: View {
    @Bindable var store: AppStore
    let loginState: LoginState

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header
                credentialsCard
                sitesCard
                connectButton
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 28)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MoDyt")
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
            Text("Control your home with live Tydom data.")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var credentialsCard: some View {
        VStack(spacing: 16) {
            TextField(
                "Email",
                text: Binding(
                    get: { loginState.email },
                    set: { store.send(.loginEmailChanged($0)) }
                )
            )
#if os(iOS)
            .textInputAutocapitalization(.never)
#endif
            .textFieldStyle(.roundedBorder)

            SecureField(
                "Password",
                text: Binding(
                    get: { loginState.password },
                    set: { store.send(.loginPasswordChanged($0)) }
                )
            )
            .textFieldStyle(.roundedBorder)

            Button {
                store.send(.loadSitesTapped)
            } label: {
                if loginState.isLoadingSites {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Load Sites")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!loginState.canLoadSites || loginState.isLoadingSites)

            if let error = loginState.errorMessage {
                Text(error)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .glassCard(cornerRadius: 24)
    }

    private var sitesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Sites")
                    .font(.system(.headline, design: .rounded))
                Spacer()
                Text("\(loginState.sites.count)")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            if loginState.sites.isEmpty {
                Text("Load your sites to continue.")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(loginState.sites.indices, id: \.self) { index in
                    let site = loginState.sites[index]
                    Button {
                        store.send(.siteSelected(index))
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "house")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(site.name)
                                    .font(.system(.body, design: .rounded))
                                Text("\(site.gateways.count) gateways")
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if loginState.selectedSiteIndex == index {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    if index < loginState.sites.count - 1 {
                        Divider().opacity(0.4)
                    }
                }
            }
        }
        .padding(20)
        .glassCard(cornerRadius: 24)
    }

    private var connectButton: some View {
        Button {
            store.send(.connectTapped)
        } label: {
            HStack {
                Spacer()
                if loginState.isConnecting {
                    ProgressView()
                } else {
                    Text("Connect")
                        .font(.system(.headline, design: .rounded))
                }
                Spacer()
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(!loginState.canConnect)
    }
}
