import AppKit
import LauncherCore
import UniformTypeIdentifiers

extension LauncherModel {
    func renameFolder(_ folder: ApplicationFolder) {
        LauncherDialogs.text(
            title: "Rename folder", detail: "Choose a name for this folder.", initial: folder.name
        ) { [weak self] name in
            self?.execute(.renameFolder(id: folder.id, name: name), name: "Rename folder")
        }
    }

    func createFolder(with app: ApplicationRecord, and partner: ApplicationRecord) {
        LauncherDialogs.text(
            title: "New folder",
            detail:
                "Create a folder with \(app.name) and \(partner.name). You can move other apps into it afterward.",
            initial: "New Folder", accept: "Create"
        ) { [weak self] name in
            guard let self else { return }
            let id = UUID().uuidString
            execute(
                .createFolder(
                    id: id, name: name, applicationIDs: [app.id, partner.id], destination: 0),
                name: "Create folder")
            if folder(id) != nil { openFolderID = id }
        }
    }

    func editAliases(for app: ApplicationRecord) {
        LauncherDialogs.text(
            title: "Search aliases for \(app.name)",
            detail: "Enter comma-separated names you use to find this app.",
            initial: (library.aliases[app.id] ?? []).joined(separator: ", ")
        ) { [weak self] value in
            let aliases = value.split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }.filter { !$0.isEmpty }
            self?.execute(.setAliases(applicationID: app.id, values: aliases), name: "Edit aliases")
        }
    }

    func drop(
        _ source: LauncherCore.LibraryItem, onto target: LauncherCore.LibraryItem?, insertion: Int?
    ) {
        defer {
            draggedItem = nil
            dropTarget = nil
        }
        guard canDrag, source != target else { return }
        let targetApplicationID: String? = {
            if case .application(let id) = target { return id }
            return nil
        }()
        if collection == .favorites {
            guard case .application(let id) = source else { return }
            let remaining = library.favoriteIDs.filter { $0 != id }
            let index =
                targetApplicationID.flatMap { remaining.firstIndex(of: $0) } ?? remaining.count
            execute(
                .reorderFavorite(applicationID: id, destination: index), name: "Reorder favorites")
            return
        }
        if insertion != nil {
            if let folderID = openFolderID, case .application(let id) = source {
                let remaining = (folder(folderID)?.applicationIDs ?? []).filter { $0 != id }
                let index =
                    targetApplicationID.flatMap { remaining.firstIndex(of: $0) } ?? remaining.count
                execute(
                    .moveApplicationsToFolder(
                        applicationIDs: [id], folderID: folderID, destination: index),
                    name: "Reorder folder")
            } else {
                let remaining = library.rootOrder.filter { $0 != source }
                let index = target.flatMap { remaining.firstIndex(of: $0) } ?? remaining.count
                if case .application(let id) = source {
                    execute(
                        .moveApplicationsToRoot(applicationIDs: [id], destination: index),
                        name: "Move application")
                } else {
                    execute(
                        .reorderRoot(itemID: source.id, destination: index), name: "Move folder")
                }
            }
            return
        }
        guard case .application(let sourceID) = source else { return }
        switch target {
        case .folder(let id):
            execute(
                .moveApplicationsToFolder(
                    applicationIDs: [sourceID], folderID: id,
                    destination: folder(id)?.applicationIDs.count ?? 0), name: "Move into folder")
        case .application(let targetID):
            if let folderID = openFolderID {
                let index =
                    folder(folderID)?.applicationIDs.filter { $0 != sourceID }.firstIndex(
                        of: targetID) ?? 0
                execute(
                    .moveApplicationsToFolder(
                        applicationIDs: [sourceID], folderID: folderID, destination: index),
                    name: "Reorder folder")
            } else {
                let position =
                    library.rootOrder.filter { $0 != .application(sourceID) }.firstIndex(
                        of: .application(targetID)) ?? 0
                let id = UUID().uuidString
                execute(
                    .createFolder(
                        id: id, name: "New Folder", applicationIDs: [targetID, sourceID],
                        destination: position), name: "Create folder")
                openFolderID = id
            }
        case nil:
            execute(
                .moveApplicationsToRoot(
                    applicationIDs: [sourceID], destination: library.rootOrder.count),
                name: "Move out of folder")
        }
    }

    @discardableResult
    func dropOnFavorites(_ source: LauncherCore.LibraryItem) -> Bool {
        guard canDrag, case .application(let id) = source else { return false }
        guard !library.favoriteIDs.contains(id) else { return true }
        execute(.setFavorite(applicationID: id, isFavorite: true), name: "Add to Favorites")
        guard library.favoriteIDs.contains(id) else { return false }
        confirmFavoriteDrop(for: id)
        return true
    }

    func addApplicationFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add application folder"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.updatePreferences { prefs in
                if !prefs.customApplicationFolders.contains(url) {
                    prefs.customApplicationFolders.append(url)
                }
            }
        }
    }

    func removeApplicationFolder(_ url: URL) {
        updatePreferences { $0.customApplicationFolders.removeAll { $0 == url } }
    }

    func exportLayout() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Sofla Layout.json"
        panel.begin { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                do {
                    let data = try await store.exportData(document())
                    try await LayoutFileIO.write(data, to: url)
                    message = "Layout exported without recent-use history."
                } catch { message = "The layout could not be exported." }
            }
        }
    }

    func importLayout() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                do {
                    let data = try await LayoutFileIO.read(url)
                    let document = try await store.previewImport(data)
                    LauncherDialogs.confirm(
                        title: "Import layout?",
                        detail:
                            "Replace your organization and preferences with \(document.organization.folders.count) folders and \(document.organization.favoriteIDs.count) favorites? The current layout remains available through Edit > Undo.",
                        accept: "Import"
                    ) { [weak self = self] in
                        self?.applyImport(data)
                    }
                } catch {
                    message =
                        "This file is not a supported, valid launcher layout. Nothing was changed."
                }
            }
        }
    }

    private func applyImport(_ data: Data) {
        let pendingSave = saveTask
        pendingSave?.cancel()
        saveTask = nil
        pauseCatalogUpdates()
        let previous = library
        let wasLocked = recoveryLocked
        recoveryLocked = true
        Task { @MainActor in
            await pendingSave?.value
            do {
                let preview = try await store.previewImport(data)
                let candidate = try preview.libraryState(records: previous.records)
                library = candidate
                do { try onPreferencesChanged?() } catch {
                    library = previous
                    recoveryLocked = wasLocked
                    try? onPreferencesChanged?()
                    resumeCatalogUpdates()
                    message =
                        "The imported shortcut is unavailable. Nothing was imported; choose a different shortcut in the file."
                    return
                }
                do { _ = try await store.importData(data) } catch {
                    library = previous
                    recoveryLocked = wasLocked
                    do { try onPreferencesChanged?() } catch {
                        resumeCatalogUpdates()
                        message =
                            "Import failed and the previous shortcut needs attention in Settings."
                        return
                    }
                    resumeCatalogUpdates()
                    message =
                        "Import failed. Your previous layout is still active and its file is preserved."
                    return
                }
                recoveryLocked = false
                hasBackup = false
                undoManager.removeAllActions()
                undoManager.registerUndo(withTarget: self) { model in
                    model.replaceLibraryForUndo(previous, actionName: "Import Layout")
                }
                undoManager.setActionName("Import Layout")
                clearStaleFolderSelection()
                refreshItems()
                resumeCatalogUpdates()
                message =
                    "Layout imported. Choose Edit > Undo Import Layout to restore the previous layout."
            } catch {
                library = previous
                recoveryLocked = wasLocked
                try? onPreferencesChanged?()
                resumeCatalogUpdates()
                message = "This layout could not be applied. Nothing was changed."
            }
        }
    }

    private func replaceLibraryForUndo(_ replacement: LibraryState, actionName: String) {
        let current = library
        pauseCatalogUpdates()
        do {
            let candidate = try LibraryState(
                records: current.records, preferences: replacement.preferences,
                organization: replacement.organization)
            library = candidate
            do {
                try onPreferencesChanged?()
            } catch {
                library = current
                try? onPreferencesChanged?()
                resumeCatalogUpdates()
                message =
                    "This layout cannot be restored because its keyboard shortcut is unavailable."
                return
            }
            undoManager.registerUndo(withTarget: self) { model in
                model.replaceLibraryForUndo(current, actionName: actionName)
            }
            undoManager.setActionName(actionName)
            clearStaleFolderSelection()
            refreshItems()
            resumeCatalogUpdates()
            scheduleSave()
            message = "The previous layout was restored."
        } catch {
            library = current
            resumeCatalogUpdates()
            message = "The previous layout could not be restored."
        }
    }

    func resetLayout() {
        LauncherDialogs.confirm(
            title: "Reset organization?",
            detail:
                "Remove folders, favorites, hidden choices, aliases, and recent history. Applications stay installed and preferences are kept. You can undo this change.",
            accept: "Reset organization"
        ) { [weak self = self] in
            guard let self else { return }
            execute(.resetOrganization, name: "Reset organization")
        }
    }
}

nonisolated private enum LayoutFileIO {
    @concurrent static func read(_ url: URL) async throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 8_000_001) ?? Data()
        guard data.count <= 8_000_000 else { throw CocoaError(.fileReadTooLarge) }
        return data
    }

    @concurrent static func write(_ data: Data, to url: URL) async throws {
        try data.write(to: url, options: .atomic)
    }
}
