import LauncherCore
import SwiftUI

struct GeneralPreferencesView: View {
    let model: LauncherModel

    var body: some View {
        Form {
            Section("Launcher") {
                LabeledContent("Keyboard shortcut") {
                    HStack(spacing: 8) {
                        ShortcutRecorder(shortcut: model.preferences.shortcut) { shortcut in
                            let accepted = model.updateShortcut(shortcut)
                            if accepted {
                                model.message = nil
                            } else {
                                model.message = "That keyboard shortcut is already in use."
                            }
                            return accepted
                        }
                        .accessibilityIdentifier("preferences.shortcut")

                        Button("Reset Shortcut") { model.resetShortcut() }
                            .accessibilityIdentifier("preferences.shortcutReset")
                    }
                }

                Picker("Open to", selection: rawPreferenceBinding(\.startCollection)) {
                    Text("All Apps").tag(LauncherPreferences.StartCollection.all.rawValue)
                    Text("Favorites").tag(LauncherPreferences.StartCollection.favorites.rawValue)
                    Text("Recents").tag(LauncherPreferences.StartCollection.recents.rawValue)
                }
                .accessibilityIdentifier("preferences.startCollection")
            }
            .disabled(!model.isReady || model.recoveryLocked)

            Section("Login") {
                Toggle("Open at login", isOn: loginBinding)
                    .accessibilityIdentifier("preferences.openAtLogin")
                Text(
                    "When enabled, Sofla starts hidden and preloads the catalog, wallpaper, and first pages in the background."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                if model.login.status == .requiresApproval {
                    LabeledContent("Status", value: "Approval required in System Settings")
                    Button("Open Login Items Settings") {
                        guard !model.isTesting else { return }
                        model.login.openSystemSettings()
                    }
                    .accessibilityIdentifier("preferences.loginApproval")
                } else if model.login.status == .notFound {
                    LabeledContent("Status", value: "Unavailable for this app build")
                }
            }
            .disabled(!model.isReady || model.recoveryLocked)

            Section("Recent Applications") {
                Toggle(
                    "Track recently opened applications", isOn: preferenceBinding(\.recordsRecents)
                )
                .accessibilityIdentifier("preferences.recordsRecents")

                Picker(
                    "Record applications opened", selection: rawPreferenceBinding(\.recentsScope)
                ) {
                    Text("Anywhere on this Mac").tag(
                        LauncherPreferences.RecentsScope.anywhere.rawValue)
                    Text("From Sofla").tag(
                        LauncherPreferences.RecentsScope.launcher.rawValue)
                }
                .disabled(!model.preferences.recordsRecents)
                .accessibilityIdentifier("preferences.recentsScope")

                Stepper(
                    "Keep history for \(model.preferences.retentionDays) days",
                    value: preferenceBinding(\.retentionDays),
                    in: LauncherPreferences.retentionDaysRange
                )
                .disabled(!model.preferences.recordsRecents)
                .accessibilityIdentifier("preferences.retentionDays")

                Stepper(
                    "Keep at most \(model.preferences.maximumRecentsCount) recent applications",
                    value: preferenceBinding(\.maximumRecentsCount),
                    in: 1...200
                )
                .disabled(!model.preferences.recordsRecents)
                .accessibilityIdentifier("preferences.maximumRecentsCount")

                Text(
                    "Recent application names and access times stay on this Mac. Hidden applications are excluded."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("preferences.recentsLocalOnly")

                Button("Clear Recent History", role: .destructive) {
                    model.execute(.clearRecents, name: "Clear Recent History")
                }
                .disabled(model.library.recents.isEmpty)
                .accessibilityIdentifier("preferences.clearRecents")
            }
            .disabled(!model.isReady || model.recoveryLocked)

            if let message = model.message ?? model.catalogMessage {
                Section {
                    Text(message)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("preferences.message")
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var loginBinding: Binding<Bool> {
        Binding(
            get: { model.login.status == .enabled || model.login.status == .requiresApproval },
            set: { enabled in
                guard !model.isTesting else { return }
                do {
                    try model.login.setEnabledByUser(enabled)
                } catch {
                    model.message = "Couldn’t update Open at Login: \(error.localizedDescription)"
                }
            }
        )
    }

    private func preferenceBinding<Value: Sendable>(
        _ keyPath: WritableKeyPath<LauncherPreferences, Value>
    )
        -> Binding<Value>
    {
        Binding(
            get: { model.preferences[keyPath: keyPath] },
            set: { value in
                model.updatePreferences { $0[keyPath: keyPath] = value }
            }
        )
    }

    private func rawPreferenceBinding<Value>(
        _ keyPath: WritableKeyPath<LauncherPreferences, Value>
    ) -> Binding<String> where Value: RawRepresentable & Sendable, Value.RawValue == String {
        Binding(
            get: { model.preferences[keyPath: keyPath].rawValue },
            set: { rawValue in
                guard let value = Value(rawValue: rawValue) else { return }
                model.updatePreferences { $0[keyPath: keyPath] = value }
            }
        )
    }
}
