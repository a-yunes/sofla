import LauncherCore
import SwiftUI

struct ApplicationActions: View {
    let model: LauncherModel
    let app: ApplicationRecord

    var body: some View {
        if model.library.records.contains(where: { $0.id != app.id && $0.name == app.name }) {
            Text(app.url.path)
            Divider()
        }
        Button("Open") { model.activate(.application(app.id)) }
        Button(
            model.library.favoriteIDs.contains(app.id)
                ? "Remove from Favorites" : "Add to Favorites"
        ) {
            model.execute(
                .setFavorite(
                    applicationID: app.id, isFavorite: !model.library.favoriteIDs.contains(app.id)),
                name: "Change favorite")
        }
        Menu("Move to Folder") {
            ForEach(model.library.folders) { folder in
                Button(folder.name) {
                    model.execute(
                        .moveApplicationsToFolder(
                            applicationIDs: [app.id], folderID: folder.id,
                            destination: folder.applicationIDs.count), name: "Move to folder")
                }
            }
            Menu("New folder with") {
                ForEach(model.library.visibleRecords.filter { $0.id != app.id }) { other in
                    Button(other.name) { model.createFolder(with: app, and: other) }
                }
            }
        }
        if model.openFolderID != nil {
            Button("Move out of folder") {
                model.execute(
                    .moveApplicationsToRoot(
                        applicationIDs: [app.id], destination: model.library.rootOrder.count),
                    name: "Move out of folder")
            }
        }
        Button("Move to beginning") {
            model.execute(
                .moveApplicationsToRoot(applicationIDs: [app.id], destination: 0),
                name: "Move application")
        }
        Divider()
        Button("Search aliases…") { model.editAliases(for: app) }
        Button("Hide App") {
            model.execute(
                .setHidden(applicationID: app.id, isHidden: true), name: "Hide application")
        }
        Button("Reveal in Finder") {
            guard !model.isTesting else { return }
            NSWorkspace.shared.activateFileViewerSelecting([app.url])
        }
        Divider()
        if model.canMoveToTrash(app) {
            Button("Move to Trash...") { model.requestMoveToTrash(app) }
                .accessibilityIdentifier("applicationActions.moveToTrash")
        }
        Button("Restore Alphabetical Order") { model.restoreAlphabeticalOrder() }
    }
}
