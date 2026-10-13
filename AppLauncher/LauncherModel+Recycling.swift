import AppKit
import LauncherCore

extension LauncherModel {
    func canMoveToTrash(_ app: ApplicationRecord) -> Bool {
        trashEligibleIDs.contains(app.id)
    }

    func prepareTrashEligibility(for app: ApplicationRecord) async {
        let isEligible = await ApplicationTrashEligibility.evaluate(
            app.url, appLauncherURL: Bundle.main.bundleURL)
        guard record(app.id)?.url == app.url else { return }
        if isEligible {
            trashEligibleIDs.insert(app.id)
        } else {
            trashEligibleIDs.remove(app.id)
        }
    }

    func requestMoveToTrash(_ app: ApplicationRecord) {
        guard canMoveToTrash(app) else { return }
        trashEligibilityTask?.cancel()
        trashEligibilityTask = Task { @MainActor [weak self] in
            defer { self?.trashEligibilityTask = nil }
            guard let self else { return }
            let isEligible = await ApplicationTrashEligibility.evaluate(
                app.url, appLauncherURL: Bundle.main.bundleURL)
            guard !Task.isCancelled, isEligible, record(app.id)?.url == app.url else {
                trashEligibleIDs.remove(app.id)
                return
            }
            LauncherDialogs.confirm(
                title: "Move \(app.name) to Trash?",
                detail:
                    "This moves \(app.name) to the Trash.\n\nPath: \(app.url.path)\n\nYou can recover it from the Trash.",
                accept: "Move to Trash"
            ) { [weak self] in
                self?.performMoveToTrash(app)
            }
        }
    }

    func performMoveToTrash(_ app: ApplicationRecord) {
        recycleTask?.cancel()
        recycleTask = Task { @MainActor [weak self] in
            defer { self?.recycleTask = nil }
            guard let self else { return }
            let isEligible = await ApplicationTrashEligibility.evaluate(
                app.url, appLauncherURL: Bundle.main.bundleURL)
            guard !Task.isCancelled, isEligible, record(app.id)?.url == app.url else {
                trashEligibleIDs.remove(app.id)
                return
            }
            do {
                let newURLs = try await recycler.recycle(app.url)
                guard newURLs[app.url] != nil || newURLs[app.url.standardizedFileURL] != nil else {
                    message = "Could not move \(app.name) to Trash. Nothing was changed."
                    return
                }
                message = "Moved \(app.name) to Trash. You can recover it from the Trash."
                onCatalogRefresh?()
                refreshCatalog()
            } catch {
                message = "Could not move \(app.name) to Trash: \(error.localizedDescription)"
            }
        }
    }
}
