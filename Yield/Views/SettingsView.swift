import SwiftUI

struct SettingsView: View {
    @AppStorage("harvestToken") private var harvestToken = ""
    @AppStorage("harvestAccountId") private var harvestAccountId = ""
    @AppStorage("forecastAccountId") private var forecastAccountId = ""

    @State private var testStatus: String? = nil
    @State private var isTesting = false

    var body: some View {
        Form {
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
        .formStyle(.grouped)
        .frame(width: 400, height: 320)
        .navigationTitle("Yield Settings")
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
