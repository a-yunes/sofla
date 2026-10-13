import SwiftUI

struct UpdatesPreferencesView: View {
    let updates: UpdateService

    var body: some View {
        Form {
            Section("Software Updates") {
                LabeledContent(
                    "Sofla version",
                    value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
                        as? String ?? "Unknown")
                Toggle(
                    "Automatically check for updates",
                    isOn: Binding(
                        get: { updates.automaticChecks }, set: updates.setAutomaticChecks)
                )
                .accessibilityIdentifier("preferences.updateChecks")
                Toggle(
                    "Automatically download and install updates",
                    isOn: Binding(
                        get: { updates.automaticDownloads }, set: updates.setAutomaticDownloads)
                )
                .disabled(!updates.automaticChecks)
                .accessibilityIdentifier("preferences.updateDownloads")
                Text(
                    "Automatic installs happen when you quit Sofla. You can also install an update now."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                Button("Check for Updates…") { updates.checkForUpdates(nil) }
                    .disabled(!updates.canCheck)
                    .accessibilityIdentifier("preferences.checkForUpdates")
                if let lastChecked = updates.lastChecked {
                    LabeledContent("Last checked", value: lastChecked.formatted())
                        .accessibilityIdentifier("preferences.lastUpdateCheck")
                }
            }
            Section {
                Text(
                    "Updates come from Sofla’s GitHub releases and are verified before installation. No app inventory or usage analytics is sent."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                if let error = updates.error { Text(error).foregroundStyle(.secondary) }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
