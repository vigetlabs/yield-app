import SwiftUI

struct SettingsView: View {
    let oAuthService: OAuthService

    @AppStorage("appearanceMode") private var appearanceMode: String = AppearanceMode.system.rawValue

    var body: some View {
        Form {
            if oAuthService.isAuthenticated {
                oauthConnectedSection
            } else {
                oauthSignInSection
            }

            Section {
                Picker("Appearance", selection: .constant(AppearanceMode.dark.rawValue)) {
                    ForEach(AppearanceMode.allCases, id: \.rawValue) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(true)
            }

        }
        .formStyle(.grouped)
        .frame(width: 400, height: oAuthService.isAuthenticated ? 280 : 320)
        .navigationTitle("Yield Settings")
    }

    // MARK: - OAuth Connected

    private var oauthConnectedSection: some View {
        Section {
            if let name = oAuthService.userName {
                LabeledContent("Signed in as", value: name)
            }
            if let harvestId = oAuthService.harvestAccountId {
                LabeledContent("Harvest Account", value: harvestId)
            }
            if let forecastId = oAuthService.forecastAccountId {
                LabeledContent("Forecast Account", value: forecastId)
            }

            Button("Sign Out") {
                oAuthService.signOut()
                Task {
                    await AppState.shared.viewModel.refresh()
                }
            }
        } header: {
            Text("Harvest Account")
        }
    }

    // MARK: - OAuth Sign In

    private var oauthSignInSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Sign in with your Harvest account to get started. This will also connect your Forecast data automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(action: {
                    oAuthService.startOAuthFlow()
                }) {
                    if oAuthService.isAuthenticating {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Sign in with Harvest")
                    }
                }
                .disabled(oAuthService.isAuthenticating)

                if let error = oAuthService.authError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        } header: {
            Text("Harvest Account")
        }
    }

}
