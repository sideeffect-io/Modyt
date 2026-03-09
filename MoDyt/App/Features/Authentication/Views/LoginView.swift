import SwiftUI
import DeltaDoreClient

struct LoginView: View {
    private enum Field: Hashable {
        case email
        case password
    }

    @Bindable var store: AuthenticationStore
    let loginState: LoginState
    @FocusState private var focusedField: Field?

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
                text: emailBinding
            )
#if os(iOS)
            .textInputAutocapitalization(.never)
#endif
            .autocorrectionDisabled()
            .keyboardType(.emailAddress)
            .textContentType(.username)
            .submitLabel(.next)
            .focused($focusedField, equals: .email)
            .onSubmit {
                focusedField = .password
            }
            .textFieldStyle(.roundedBorder)

            SecureField(
                "Password",
                text: passwordBinding
            )
            .textContentType(.password)
            .submitLabel(.go)
            .focused($focusedField, equals: .password)
            .onSubmit {
                loadSites()
            }
            .textFieldStyle(.roundedBorder)

            Button {
                loadSites()
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
                let lastSiteID = loginState.sites.last?.id

                ForEach(loginState.sites, id: \.id) { site in
                    Button {
                        store.send(.siteSelected(site.id))
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
                            if loginState.selectedSiteID == site.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    if site.id != lastSiteID {
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

    private var emailBinding: Binding<String> {
        Binding(
            get: { loginState.email },
            set: { store.send(.loginEmailChanged($0)) }
        )
    }

    private var passwordBinding: Binding<String> {
        Binding(
            get: { loginState.password },
            set: { store.send(.loginPasswordChanged($0)) }
        )
    }

    private func loadSites() {
        guard loginState.canLoadSites, !loginState.isLoadingSites else { return }
        store.send(.loadSitesTapped)
    }
}
