import SwiftUI
import MoDytCore

#if os(macOS)
import AppKit
#endif

struct AuthFlowView: View {
    @Bindable var store: AppStore

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            VStack(spacing: 12) {
                Text("Welcome to MoDyt")
                    .font(.largeTitle.bold())

                Text("Connect to your Tydom gateway")
                    .foregroundStyle(.secondary)
            }

            switch store.state.authStatus {
            case .selectingSite(let sites):
                SitePickerView(sites: sites) { index in
                    store.send(.siteSelected(index))
                }
            default:
                credentialsForm
            }

            if let error = store.state.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.footnote)
            }

            Spacer()
        }
        .padding(32)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(appBackground)
    }

    private var credentialsForm: some View {
        VStack(spacing: 16) {
            TextField("Email", text: binding(\.email))
                .textContentType(.username)
                .applyEmailStyle()

            SecureField("Password", text: binding(\.password))
                .textContentType(.password)
                .applyPasswordStyle()

            expertSection

            Button {
                store.send(.connectRequested)
            } label: {
                if store.state.authStatus == .connecting {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Connect")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.state.authStatus == .connecting)
        }
    }

    private var expertSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(store.state.authForm.expert.isEnabled ? "Hide Expert Mode" : "Show Expert Mode") {
                updateForm { form in
                    form.expert.isEnabled.toggle()
                }
            }
            .buttonStyle(.plain)

            if store.state.authForm.expert.isEnabled {
                Picker("Connection mode", selection: expertBinding(\.connectionMode)) {
                    Text("Auto").tag(ConnectionMode.auto)
                    Text("Force local").tag(ConnectionMode.forceLocal)
                    Text("Force remote").tag(ConnectionMode.forceRemote)
                }
                .pickerStyle(.segmented)

                if store.state.authForm.expert.connectionMode == .forceLocal {
                    TextField("Local IP override", text: expertBinding(\.localHostOverride))
                        .applyDefaultStyle()

                    TextField("Gateway MAC override", text: expertBinding(\.macOverride))
                        .applyDefaultStyle()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func binding<T>(_ keyPath: WritableKeyPath<AuthForm, T>) -> Binding<T> {
        Binding(
            get: { store.state.authForm[keyPath: keyPath] },
            set: { value in
                updateForm { form in
                    form[keyPath: keyPath] = value
                }
            }
        )
    }

    private func updateForm(_ update: (inout AuthForm) -> Void) {
        var form = store.state.authForm
        update(&form)
        store.send(.authFormUpdated(form))
    }

    private func expertBinding<T>(_ keyPath: WritableKeyPath<ExpertOptions, T>) -> Binding<T> {
        Binding(
            get: { store.state.authForm.expert[keyPath: keyPath] },
            set: { value in
                updateForm { form in
                    form.expert[keyPath: keyPath] = value
                }
            }
        )
    }

    private var appBackground: some View {
        if #available(iOS 26, macOS 26, *) {
            return AnyView(
                LinearGradient(
                    colors: [.blue.opacity(0.25), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
        }
        #if os(macOS)
        return AnyView(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
        #else
        return AnyView(Color(.systemBackground).ignoresSafeArea())
        #endif
    }
}

private extension View {
    func applyEmailStyle() -> some View {
        #if os(macOS)
        return self.applyDefaultStyle()
        #else
        return self.textInputAutocapitalization(.never)
            .textFieldStyle(.roundedBorder)
        #endif
    }

    func applyPasswordStyle() -> some View {
        #if os(macOS)
        return self.applyDefaultStyle()
        #else
        return self.textFieldStyle(.roundedBorder)
        #endif
    }

    func applyDefaultStyle() -> some View {
        #if os(macOS)
        return self
            .textFieldStyle(.plain)
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.secondary.opacity(0.3))
            )
        #else
        return self.textFieldStyle(.roundedBorder)
        #endif
    }
}
