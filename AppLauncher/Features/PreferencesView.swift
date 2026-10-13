import SwiftUI

struct PreferencesView: View {
    private enum Section: String, CaseIterable, Identifiable {
        case general
        case layout
        case searchAndApps
        case updates

        var id: Self { self }

        var title: String {
            switch self {
            case .general: "General"
            case .layout: "Layout"
            case .searchAndApps: "Search & Apps"
            case .updates: "Updates"
            }
        }

        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .layout: "square.grid.3x3"
            case .searchAndApps: "magnifyingglass"
            case .updates: "arrow.down.circle"
            }
        }
    }

    let model: LauncherModel
    @State private var selection: Section? = .general

    var body: some View {
        HStack(spacing: 0) {
            List(Section.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.symbol)
                    .tag(section)
                    .accessibilityIdentifier("preferences.section.\(section.rawValue)")
            }
            .listStyle(.sidebar)
            .frame(width: 170)

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                Text((selection ?? .general).title)
                    .font(.title2.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 8)

                Group {
                    switch selection ?? .general {
                    case .general:
                        GeneralPreferencesView(model: model)
                    case .layout:
                        LayoutPreferencesView(model: model)
                    case .searchAndApps:
                        SearchAndAppsPreferencesView(model: model)
                    case .updates:
                        UpdatesPreferencesView(updates: model.updates)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 700, minHeight: 500)
        .accessibilityIdentifier("preferences.window")
    }
}
