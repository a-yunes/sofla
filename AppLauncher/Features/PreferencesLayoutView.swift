import LauncherCore
import SwiftUI

struct LayoutPreferencesView: View {
    let model: LauncherModel

    var body: some View {
        Form {
            Section("Grid") {
                Stepper(
                    "Columns: \(model.preferences.grid.columns)",
                    value: gridBinding(\.columns),
                    in: GridConfiguration.columnRange
                )
                .accessibilityIdentifier("preferences.gridColumns")

                Stepper(
                    "Rows: \(model.preferences.grid.rows)",
                    value: gridBinding(\.rows),
                    in: GridConfiguration.rowRange
                )
                .accessibilityIdentifier("preferences.gridRows")

                Picker("Icon size", selection: iconSizeBinding) {
                    Text("Small").tag(LauncherPreferences.IconSize.small.rawValue)
                    Text("Medium").tag(LauncherPreferences.IconSize.medium.rawValue)
                    Text("Large").tag(LauncherPreferences.IconSize.large.rawValue)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("preferences.iconSize")
            }

            Section("Collections") {
                Toggle("Show Favorites", isOn: preferenceBinding(\.showsFavorites))
                    .accessibilityIdentifier("preferences.showsFavorites")
                Toggle("Show Recents", isOn: preferenceBinding(\.showsRecents))
                    .accessibilityIdentifier("preferences.showsRecents")
                Toggle("Show keyboard hints", isOn: preferenceBinding(\.showsKeyboardHints))
                    .accessibilityIdentifier("preferences.keyboardHints")
            }

            Section("Interaction") {
                Picker(
                    "Page swipe sensitivity",
                    selection: rawPreferenceBinding(\.pageSwipeSensitivity)
                ) {
                    Text("Slow").tag(LauncherPreferences.PageSwipeSensitivity.slow.rawValue)
                    Text("Standard").tag(LauncherPreferences.PageSwipeSensitivity.standard.rawValue)
                    Text("Fast").tag(LauncherPreferences.PageSwipeSensitivity.fast.rawValue)
                }
                .accessibilityIdentifier("preferences.pageSwipeSensitivity")

                Picker(
                    "Dock icon appearance", selection: rawPreferenceBinding(\.dockIconAppearance)
                ) {
                    Text("System").tag(LauncherPreferences.DockIconAppearance.system.rawValue)
                    Text("Light").tag(LauncherPreferences.DockIconAppearance.light.rawValue)
                    Text("Dark").tag(LauncherPreferences.DockIconAppearance.dark.rawValue)
                }
                .accessibilityIdentifier("preferences.dockIconAppearance")

                Text(
                    "This changes the running app’s Dock and app-switcher icon only. Finder keeps the adaptive app icon."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Section("Organization") {
                Button("Restore Alphabetical Order") { model.restoreAlphabeticalOrder() }
                    .accessibilityIdentifier("preferences.restoreAlphabeticalOrder")
                Text("Sort All apps and folder contents by name. You can undo this change.")
                    .foregroundStyle(.secondary)
            }

            Section("Defaults") {
                Button("Restore Default Settings") { model.restoreDefaultSettings() }
                    .accessibilityIdentifier("preferences.restoreDefaults")
                Text(
                    "Reset app-owned behavior preferences while preserving your shortcut and organization."
                )
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Section("System Appearance") {
                LabeledContent("Appearance", value: "Controlled by macOS")
                Text(
                    "Sofla follows the system’s appearance, accent color, contrast, transparency, and motion settings."
                )
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("preferences.systemAppearance")
            }
        }
        .formStyle(.grouped)
        .padding()
        .disabled(!model.isReady || model.recoveryLocked)
    }

    private func gridBinding(_ keyPath: KeyPath<GridConfiguration, Int>) -> Binding<Int> {
        Binding(
            get: { model.preferences.grid[keyPath: keyPath] },
            set: { value in
                let current = model.preferences.grid
                let columns = keyPath == \.columns ? value : current.columns
                let rows = keyPath == \.rows ? value : current.rows
                guard let grid = try? GridConfiguration(columns: columns, rows: rows) else {
                    return
                }
                model.updatePreferences { $0.grid = grid }
            }
        )
    }

    private var iconSizeBinding: Binding<String> {
        Binding(
            get: { model.preferences.iconSize.rawValue },
            set: { rawValue in
                guard let iconSize = LauncherPreferences.IconSize(rawValue: rawValue) else {
                    return
                }
                model.updatePreferences { $0.iconSize = iconSize }
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

    private func preferenceBinding<Value: Sendable>(
        _ keyPath: WritableKeyPath<LauncherPreferences, Value>
    )
        -> Binding<Value>
    {
        Binding(
            get: { model.preferences[keyPath: keyPath] },
            set: { value in model.updatePreferences { $0[keyPath: keyPath] = value } }
        )
    }
}
