import AppKit
import LauncherCore

extension LauncherModel {
    func dismissMessage() {
        if launchFailure != nil {
            launchFailure = nil
            lastFailedLaunch = nil
        } else if message != nil {
            message = nil
        } else {
            catalogMessage = nil
        }
    }

    func updatePreferences(
        pruningRecents: Bool = true,
        _ transform: (inout LauncherPreferences) -> Void
    ) {
        guard isReady else { return }
        guard !recoveryLocked else {
            message = "Restore or import your saved layout before changing preferences."
            return
        }
        let previous = library.preferences
        var next = previous
        transform(&next)
        do {
            try next.validate()
            library.preferences = next
            try onPreferencesChanged?()
            if previous.customApplicationFolders != next.customApplicationFolders {
                restartCatalogForChangedRoots()
            }
            if !next.showsFavorites && collection == .favorites { collection = .all }
            if !next.showsRecents && collection == .recents { collection = .all }
            if pruningRecents { pruneRecents() }
            refreshItems()
            scheduleSave()
        } catch {
            library.preferences = previous
            try? onPreferencesChanged?()
            message = "Could not apply this preference. Check the value or choose another shortcut."
        }
    }

    @discardableResult func updateShortcut(_ shortcut: HotKeyPreference) -> Bool {
        updatePreferences { $0.shortcut = shortcut }
        return preferences.shortcut == shortcut
    }

    func resetShortcut() {
        let defaultShortcut = LauncherPreferences().shortcut
        updatePreferences { $0.shortcut = defaultShortcut }
    }

    func restoreDefaultSettings() {
        let shortcut = preferences.shortcut
        updatePreferences(pruningRecents: false) {
            $0 = LauncherPreferences.defaults(preservingShortcut: shortcut)
        }
    }

    func execute(_ command: LibraryCommand, name: String) {
        guard isReady else { return }
        guard !recoveryLocked else {
            message = "Restore or import your saved layout before changing its organization."
            return
        }
        do {
            let inverse = try library.apply(command)
            clearStaleFolderSelection()
            undoManager.registerUndo(withTarget: self) { model in model.execute(inverse, name: name)
            }
            undoManager.setActionName(name)
            refreshItems()
            scheduleSave()
        } catch { message = organizationErrorMessage(error) }
    }

    func restoreAlphabeticalOrder() {
        execute(.restoreAlphabeticalOrder, name: "Restore Alphabetical Order")
    }

    private func organizationErrorMessage(_ error: any Error) -> String {
        switch error as? LibraryError {
        case .emptyFolderName: "Enter a name for the folder."
        case .folderNameTooLong: "Folder names can contain at most 80 characters."
        case .folderRequiresApplications: "Choose at least two applications for a new folder."
        case .emptyAlias: "Search aliases cannot be empty."
        case .duplicateAlias: "Use each search alias only once for an application."
        case .aliasCollision: "That search alias is already assigned to another application."
        case .aliasLimitExceeded: "Use up to 32 aliases, each no longer than 80 characters."
        case .unknownApplicationReference, .itemNotFound:
            "This application is no longer available in the catalog."
        case .folderNotFound: "This folder no longer exists."
        default: "This change could not be applied. Your existing organization has been preserved."
        }
    }

}
