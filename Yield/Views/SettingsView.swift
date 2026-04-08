import ServiceManagement
import SwiftUI

struct SettingsView: View {
    let oAuthService: OAuthService

    @AppStorage("appearanceMode") private var appearanceMode: String = AppearanceMode.system.rawValue
    @AppStorage("idleDetectionEnabled") private var idleDetectionEnabled = true
    @AppStorage("idleMinutes") private var idleMinutes = 10
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            if oAuthService.isAuthenticated {
                oauthConnectedSection
            } else {
                oauthSignInSection
            }

            Section {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            // Revert toggle if registration fails
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }

                Picker("Appearance", selection: .constant(AppearanceMode.dark.rawValue)) {
                    ForEach(AppearanceMode.allCases, id: \.rawValue) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(true)

                HStack {
                    Toggle("Detect idle time after", isOn: $idleDetectionEnabled)
                    TextField("", value: $idleMinutes, format: .number)
                        .frame(width: 40)
                        .multilineTextAlignment(.center)
                        .disabled(!idleDetectionEnabled)
                    Text("minutes of inactivity")
                        .foregroundStyle(idleDetectionEnabled ? .primary : .secondary)
                }
            }

        }
        .formStyle(.grouped)
        .frame(width: 400, height: oAuthService.isAuthenticated ? 320 : 350)
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
