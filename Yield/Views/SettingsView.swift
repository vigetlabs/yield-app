import SwiftUI

struct SettingsView: View {
    let oAuthService: OAuthService

    @AppStorage("harvestToken") private var harvestToken = ""
    @AppStorage("harvestAccountId") private var harvestAccountId = ""
    @AppStorage("forecastAccountId") private var forecastAccountId = ""

    @State private var testStatus: String? = nil
    @State private var isTesting = false
    @State private var showAdvanced = false

    var body: some View {
        Form {
            if oAuthService.isAuthenticated {
                oauthConnectedSection
            } else {
                oauthSignInSection
            }

            DisclosureGroup("Advanced: Personal Access Token", isExpanded: $showAdvanced) {
                patSection
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: oAuthService.isAuthenticated ? 320 : 380)
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

    // MARK: - PAT Section

    private var patSection: some View {
        Group {
            Section {
                Text("Generate a personal access token at:")
                Link("id.getharvest.com/developers",
                     destination: URL(string: "https://id.getharvest.com/developers")!)
                    .font(.caption)
            } header: {
                Text("Setup")
            }

            Section {
                SecureField("Access Token", text: $harvestToken)
                TextField("Harvest Account ID", text: $harvestAccountId)
                TextField("Forecast Account ID", text: $forecastAccountId)
            } header: {
                Text("API Credentials")
            }

            Section {
                Button(action: testConnection) {
                    if isTesting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Test Connection")
                    }
                }
                .disabled(isTesting || harvestToken.isEmpty || harvestAccountId.isEmpty || forecastAccountId.isEmpty)

                if let status = testStatus {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(status.contains("Success") ? .green : .red)
                }
            }
        }
    }

    private func testConnection() {
        isTesting = true
        testStatus = nil

        Task {
            let harvest = HarvestService(token: harvestToken, accountId: harvestAccountId)
            let forecast = ForecastService(token: forecastToken, accountId: forecastAccountId)

            do {
                async let harvestUser = harvest.getCurrentUser()
                async let forecastPerson = forecast.getCurrentPerson()

                let user = try await harvestUser
                let person = try await forecastPerson

                await MainActor.run {
                    testStatus = "Success! Harvest: \(user.firstName) \(user.lastName), Forecast ID: \(person.id)"
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    testStatus = "Error: \(error.localizedDescription)"
                    isTesting = false
                }
            }
        }
    }

    private var forecastToken: String { harvestToken }
}
