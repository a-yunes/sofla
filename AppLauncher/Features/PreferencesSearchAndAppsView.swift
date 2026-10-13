import LauncherCore
import SwiftUI

struct SearchAndAppsPreferencesView: View {
    private enum ApplicationFilter: String, CaseIterable, Identifiable {
        case all
        case hidden

        var id: Self { self }

        var title: String {
            switch self {
            case .all: "All"
            case .hidden: "Hidden"
            }
        }
    }

    let model: LauncherModel
    @State private var applicationQuery = ""
    @State private var applicationFilter: ApplicationFilter = .all

    var body: some View {
        Form {
            Section("Search") {
                Toggle("Allow typo-tolerant matching", isOn: typoToleranceBinding)
                    .accessibilityIdentifier("preferences.typoTolerance")
                Text(
                    "Aliases are local names that help an application appear for your own search terms."
                )
                .foregroundStyle(.secondary)
            }

            Section("Application Folders") {
                ForEach(model.preferences.customApplicationFolders, id: \.standardizedFileURL) {
                    url in
                    LabeledContent {
                        Button("Remove", role: .destructive) {
                            model.removeApplicationFolder(url)
                        }
                        .accessibilityLabel("Remove \(url.lastPathComponent)")
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(url.lastPathComponent)
                            Text(url.deletingLastPathComponent().path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }

                Button("Add Application Folder…") {
                    model.addApplicationFolder()
                }
                .disabled(
                    model.preferences.customApplicationFolders.count
                        >= LauncherPreferences.maximumCustomApplicationFolders
                )
                .accessibilityIdentifier("preferences.addApplicationFolder")
            }

            Section("Applications") {
                Picker("Application filter", selection: $applicationFilter) {
                    ForEach(ApplicationFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("preferences.applicationFilter")

                TextField("Find an application", text: $applicationQuery)
                    .textFieldStyle(.automatic)
                    .accessibilityIdentifier("preferences.applicationSearch")

                if matchingApplications.isEmpty {
                    Text(
                        applicationQuery.isEmpty
                            ? applicationFilter == .hidden
                                ? "No hidden applications." : "No applications found."
                            : "No matching applications."
                    )
                    .foregroundStyle(.secondary)
                } else {
                    ForEach(matchingApplications) { application in
                        applicationRow(application)
                    }
                }
            }

            Section("Data") {
                HStack {
                    Button("Import…") { model.importLayout() }
                        .accessibilityIdentifier("preferences.importLayout")
                    Button("Export…") { model.exportLayout() }
                        .accessibilityIdentifier("preferences.exportLayout")
                    Spacer()
                    Button("Reset…", role: .destructive) { model.resetLayout() }
                        .accessibilityIdentifier("preferences.resetLayout")
                }

                if model.recoveryLocked {
                    LabeledContent {
                        Button("Restore Backup") { model.restoreBackup() }
                            .accessibilityIdentifier("preferences.restoreBackup")
                    } label: {
                        Text("Saved layout needs recovery")
                    }
                }
            }

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
        .accessibilityIdentifier("preferences.detail.searchAndApps")
    }

    @ViewBuilder
    private func applicationRow(_ application: ApplicationRecord) -> some View {
        LabeledContent {
            HStack {
                Button("Edit Aliases…") {
                    model.editAliases(for: application)
                }
                .accessibilityLabel("Edit aliases for \(application.name)")
                .accessibilityIdentifier("preferences.editAliases.\(application.id)")

                if model.library.hiddenIDs.contains(application.id) {
                    Button("Unhide") {
                        model.execute(
                            .setHidden(applicationID: application.id, isHidden: false),
                            name: "Unhide \(application.name)"
                        )
                    }
                    .accessibilityLabel("Unhide \(application.name)")
                    .accessibilityIdentifier("preferences.unhide.\(application.id)")
                } else {
                    Button("Hide") {
                        model.execute(
                            .setHidden(applicationID: application.id, isHidden: true),
                            name: "Hide \(application.name)"
                        )
                    }
                    .accessibilityLabel("Hide \(application.name)")
                    .accessibilityIdentifier("preferences.hide.\(application.id)")
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(application.name)
                let aliases = model.library.aliases[application.id] ?? []
                Text(
                    aliases.isEmpty
                        ? "Aliases: None" : "Aliases: \(aliases.joined(separator: ", "))"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .accessibilityIdentifier("preferences.aliases.\(application.id)")
            }
            .accessibilityIdentifier("preferences.applicationRow.\(application.id)")
        }
    }

    private var matchingApplications: [ApplicationRecord] {
        let records = model.library.records.filter {
            applicationFilter == .hidden
                ? model.library.hiddenIDs.contains($0.id)
                : true
        }
        let query = applicationQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return records.sorted(by: applicationSort) }
        return records.filter { application in
            application.name.localizedStandardContains(query)
                || (model.library.aliases[application.id] ?? []).contains {
                    $0.localizedStandardContains(query)
                }
        }.sorted(by: applicationSort)
    }

    private var typoToleranceBinding: Binding<Bool> {
        Binding(
            get: { model.preferences.typoTolerance },
            set: { value in model.updatePreferences { $0.typoTolerance = value } }
        )
    }

    private func applicationSort(_ lhs: ApplicationRecord, _ rhs: ApplicationRecord) -> Bool {
        let comparison = lhs.name.localizedStandardCompare(rhs.name)
        return comparison == .orderedAscending
            || (comparison == .orderedSame && lhs.id < rhs.id)
    }
}
