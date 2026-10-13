import Foundation
import Testing

@testable import LauncherCore

struct LibraryStateTests {
    @Test
    func freshStateUsesAutomaticAlphabeticalOrderAndStableIDTies() throws {
        let state = try LibraryState(records: [
            record("z", "Same Name"),
            record("a", "same  name"),
            record("b", "Beta"),
        ])

        #expect(state.orderingMode == .automatic)
        #expect(
            state.rootOrder == [
                .application("b"), .application("a"), .application("z"),
            ])
    }

    @Test
    func automaticReconciliationMergesNewAppsIntoTheFullSortedRootOrder() throws {
        var state = try LibraryState(records: [record("b", "Beta"), record("d", "Delta")])

        _ = try state.reconcileCatalog([
            record("d", "Delta"), record("a", "Alpha"), record("c", "Charlie"),
            record("b", "Beta"),
        ])

        #expect(state.orderingMode == .automatic)
        #expect(
            state.rootOrder == [
                .application("a"), .application("b"), .application("c"), .application("d"),
            ])
    }

    @Test
    func manualReconciliationAppendsNewAppsWithoutReorderingExistingRoot() throws {
        var state = try LibraryState(records: [record("a", "Alpha"), record("b", "Beta")])
        _ = try state.apply(.reorderRoot(itemID: "application:b", destination: 0))

        _ = try state.reconcileCatalog([
            record("c", "Charlie"), record("a", "Alpha"), record("b", "Beta"),
        ])

        #expect(state.orderingMode == .manual)
        #expect(
            state.rootOrder == [
                .application("b"), .application("a"), .application("c"),
            ])
    }

    @Test
    func placementCommandsEnterManualModeButMetadataCommandsDoNot() throws {
        var state = try LibraryState(records: records)
        #expect(state.orderingMode == .automatic)

        _ = try state.apply(.setFavorite(applicationID: "a", isFavorite: true))
        _ = try state.apply(.setAliases(applicationID: "a", values: ["Alpha App"]))
        _ = try state.apply(.setHidden(applicationID: "a", isHidden: true))
        _ = try state.apply(
            .replaceRecents([
                RecentApplication(applicationID: "a", accessedAt: Date(timeIntervalSince1970: 1))
            ]))
        #expect(state.orderingMode == .automatic)

        _ = try state.apply(.reorderRoot(itemID: "application:c", destination: 0))
        #expect(state.orderingMode == .manual)
        _ = try state.apply(.setFavorite(applicationID: "b", isFavorite: true))
        #expect(state.orderingMode == .manual)
    }

    @Test
    func resetOrganizationReturnsToAutomaticAlphabeticalStateAndIsUndoable() throws {
        var state = try LibraryState(
            records: [record("b", "Beta"), record("a", "Alpha")],
            organization: OrganizationSnapshot(
                rootOrder: [.application("b"), .application("a")],
                favoriteIDs: ["b"], hiddenIDs: ["a"],
                orderingMode: .manual
            ))
        let original = state.organization

        let undo = try state.apply(.resetOrganization)

        #expect(state.orderingMode == .automatic)
        #expect(state.rootOrder == [.application("a"), .application("b")])
        #expect(state.folders.isEmpty)
        #expect(state.favoriteIDs.isEmpty)
        #expect(state.hiddenIDs.isEmpty)
        #expect(state.aliases.isEmpty)
        #expect(state.recents.isEmpty)

        _ = try state.apply(undo)
        #expect(state.organization == original)
    }

    @Test
    func organizationCommandsAreUndoableAsOneValueTransaction() throws {
        var state = try LibraryState(records: records)
        let original = state
        let undo = try state.apply(
            .createFolder(id: "folder", name: " Work ", applicationIDs: ["a", "b"], destination: 0))
        #expect(state.folders.first?.name == "Work")
        #expect(state.rootOrder == [.folder("folder"), .application("c")])
        _ = try state.apply(undo)
        #expect(state == original)
    }

    @Test
    func failedCommandRollsBackPartialMutation() throws {
        var state = try LibraryState(records: records)
        let original = state
        #expect(throws: LibraryError.emptyFolderName) {
            try state.apply(
                .createFolder(id: "bad", name: "  ", applicationIDs: ["a", "b"], destination: 0))
        }
        #expect(state == original)
    }

    @Test
    func favoritesHiddenAndAliasesAreIndependentOfPlacement() throws {
        var state = try LibraryState(records: records)
        _ = try state.apply(.setFavorite(applicationID: "b", isFavorite: true))
        _ = try state.apply(.setAliases(applicationID: "b", values: ["Browser"]))
        _ = try state.apply(.setHidden(applicationID: "b", isHidden: true))
        #expect(state.favoriteIDs == ["b"])
        #expect(state.rootOrder == records.map { .application($0.id) })
        #expect(state.search("browser").isEmpty)
        _ = try state.apply(.setHidden(applicationID: "b", isHidden: false))
        #expect(state.search("browser").first?.id == "b")
    }

    @Test
    func movesAcrossFolderAndRootAndCleansEmptyFolder() throws {
        var state = try LibraryState(records: records)
        _ = try state.apply(
            .createFolder(id: "f", name: "Folder", applicationIDs: ["a", "b"], destination: 0))
        _ = try state.apply(.moveApplicationsToRoot(applicationIDs: ["a", "b"], destination: 1))
        #expect(state.folders.isEmpty)
        #expect(state.rootOrder == [.application("c"), .application("a"), .application("b")])
    }

    @Test
    func removedApplicationsKeepRecoverableOrganizationAndNewAppsAppend() throws {
        var state = try LibraryState(records: records)
        _ = try state.apply(.setFavorite(applicationID: "a", isFavorite: true))
        let scan = [records[1], records[2], record("d", "Delta")]
        let result = try state.reconcileCatalog(scan)
        #expect(result.removedIDs == ["a"])
        #expect(state.favoriteIDs == ["a"])
        #expect(state.rootOrder.last == .application("d"))
        _ = try state.apply(.setFavorite(applicationID: "b", isFavorite: true))
        #expect(state.favoriteIDs == ["a", "b"])
    }

    @Test
    func uniqueBundleMoveKeepsExistingReferences() throws {
        let old = ApplicationRecord(
            id: "stable", name: "Old", bundleIdentifier: "bundle",
            url: URL(fileURLWithPath: "/Old.app"))
        var state = try LibraryState(records: [old])
        _ = try state.apply(.setFavorite(applicationID: "stable", isFavorite: true))
        let moved = ApplicationRecord(
            id: "scan", name: "New", bundleIdentifier: "bundle",
            url: URL(fileURLWithPath: "/New.app"))
        let returned = try state.reconcileCatalog([moved])
        #expect(state.records.first?.id == "stable")
        #expect(state.favoriteIDs == ["stable"])
        #expect(returned.removedIDs.isEmpty)
    }

    @Test
    func invalidAliasesAndUnknownReferencesAreRejectedWithoutMutation() throws {
        var state = try LibraryState(records: records)
        let original = state
        #expect(throws: LibraryError.duplicateAlias) {
            try state.apply(.setAliases(applicationID: "a", values: ["Mail", "máil"]))
        }
        #expect(throws: LibraryError.unknownApplicationReference) {
            try state.apply(.setHidden(applicationID: "missing", isHidden: true))
        }
        #expect(state == original)
    }

    @Test
    func everyOrganizationCommandHasDeterministicBehavior() throws {
        var state = try LibraryState(records: records)
        #expect(state.rootOrder.map(\.id) == ["application:a", "application:b", "application:c"])
        _ = try state.apply(.reorderRoot(itemID: "application:c", destination: 0))
        _ = try state.apply(
            .createFolder(id: "f", name: "Folder", applicationIDs: ["a", "b"], destination: 1))
        _ = try state.apply(.renameFolder(id: "f", name: "Renamed"))
        _ = try state.apply(
            .moveApplicationsToFolder(applicationIDs: ["c"], folderID: "f", destination: 1))
        #expect(state.folders.first?.applicationIDs == ["a", "c", "b"])
        _ = try state.apply(.ungroupFolder(id: "f", destination: 0))
        #expect(state.rootOrder == [.application("a"), .application("c"), .application("b")])

        _ = try state.apply(.setFavorite(applicationID: "a", isFavorite: true))
        _ = try state.apply(.setFavorite(applicationID: "b", isFavorite: true))
        _ = try state.apply(.reorderFavorite(applicationID: "b", destination: 0))
        _ = try state.apply(.setFavorite(applicationID: "a", isFavorite: false))
        #expect(state.favoriteIDs == ["b"])

        _ = try state.apply(.setAliases(applicationID: "a", values: ["Zed"]))
        _ = try state.apply(.setAliases(applicationID: "a", values: []))
        _ = try state.apply(.restoreAlphabeticalOrder)
        #expect(state.rootOrder == [.application("a"), .application("b"), .application("c")])

        let recent = RecentApplication(
            applicationID: "a", accessedAt: Date(timeIntervalSince1970: 1))
        _ = try state.apply(.replaceRecents([recent]))
        #expect(state.recents == [recent])
        _ = try state.apply(.clearRecents)
        #expect(state.recents.isEmpty)
        _ = try state.apply(.setHidden(applicationID: "b", isHidden: true))
        #expect(state.visibleRecords.map(\.id) == ["a", "c"])
    }

    @Test
    func alphabeticalRestoreSortsRootAndFoldersAsOneUndoableCommand() throws {
        let gamma = record("g", "Gamma")
        let alpha = record("a", "Alpha")
        let delta = record("d", "Delta")
        let beta = record("b", "Beta")
        let folder = try ApplicationFolder(
            id: "work", name: "Work", applicationIDs: ["d", "b"])
        var state = try LibraryState(
            records: [gamma, alpha, delta, beta],
            organization: OrganizationSnapshot(
                rootOrder: [.application("g"), .folder("work"), .application("a")],
                folders: [folder],
                favoriteIDs: ["g", "a"], orderingMode: .manual
            ))
        let original = state.organization
        #expect(state.orderingMode == .manual)

        let undo = try state.apply(.restoreAlphabeticalOrder)

        #expect(state.orderingMode == .automatic)
        #expect(
            state.rootOrder == [
                .application("a"), .application("g"), .folder("work"),
            ])
        #expect(state.folders.first?.applicationIDs == ["b", "d"])
        #expect(state.favoriteIDs == ["g", "a"])

        _ = try state.apply(undo)
        #expect(state.organization == original)
        #expect(state.orderingMode == .manual)

        _ = try state.apply(.restoreAlphabeticalOrder)
        _ = try state.apply(.reorderRoot(itemID: "application:g", destination: 0))
        #expect(state.rootOrder.first == .application("g"))
    }

    @Test
    func invalidOrganizationShapesAndCommandsAreRejected() throws {
        #expect(throws: LibraryError.folderNameTooLong) {
            try ApplicationFolder(
                id: "f", name: String(repeating: "x", count: 81), applicationIDs: [])
        }
        #expect(throws: LibraryError.emptyIdentifier) {
            try ApplicationFolder(id: "", name: "Folder", applicationIDs: [])
        }
        #expect(throws: LibraryError.duplicateReference) {
            try ApplicationFolder(id: "f", name: "Folder", applicationIDs: ["a", "a"])
        }
        #expect(throws: LibraryError.duplicateRecordID) {
            try LibraryState(records: [record("a", "One"), record("a", "Two")])
        }
        #expect(throws: LibraryError.invalidApplicationRecord) {
            try LibraryState(records: [
                ApplicationRecord(
                    id: "a", name: " ", bundleIdentifier: nil, url: URL(fileURLWithPath: "/A.app"))
            ])
        }

        var state = try LibraryState(records: records)
        #expect(throws: LibraryError.itemNotFound) {
            try state.apply(.reorderRoot(itemID: "missing", destination: 0))
        }
        #expect(throws: LibraryError.folderRequiresApplications) {
            try state.apply(
                .createFolder(id: "f", name: "Folder", applicationIDs: ["a"], destination: 0))
        }
        #expect(throws: LibraryError.folderNotFound) {
            try state.apply(.renameFolder(id: "missing", name: "Name"))
        }
        #expect(throws: LibraryError.folderNotFound) {
            try state.apply(.ungroupFolder(id: "missing", destination: 0))
        }
        #expect(throws: LibraryError.folderNotFound) {
            try state.apply(
                .moveApplicationsToFolder(
                    applicationIDs: ["a"], folderID: "missing", destination: 0))
        }
        #expect(throws: LibraryError.itemNotFound) {
            try state.apply(.reorderFavorite(applicationID: "a", destination: 0))
        }
        #expect(throws: LibraryError.duplicateReference) {
            try state.apply(.moveApplicationsToRoot(applicationIDs: ["a", "a"], destination: 0))
        }
    }

    @Test
    func loadedOrganizationAppendsKnownUnplacedAppsAndRejectsAliasCollisions() throws {
        let saved = OrganizationSnapshot(rootOrder: [.application("a")])
        let loaded = try LibraryState(records: records, organization: saved)
        #expect(
            loaded.rootOrder == [
                .application("a"), .application("b"), .application("c"),
            ])

        let collision = OrganizationSnapshot(
            rootOrder: records.map { .application($0.id) },
            aliases: ["a": ["Browser"], "b": ["brówser"]]
        )
        #expect(throws: LibraryError.aliasCollision("browser")) {
            try LibraryState(records: records, organization: collision)
        }
    }

    @Test
    func disappearedApplicationReappearsAtNewURLWithOrganizationIntact() throws {
        let old = ApplicationRecord(
            id: "stable", name: "App", bundleIdentifier: "com.example.app",
            url: URL(fileURLWithPath: "/Applications/App.app"))
        let folder = try ApplicationFolder(
            id: "folder", name: "Folder", applicationIDs: ["stable"])
        var state = try LibraryState(
            records: [old],
            organization: OrganizationSnapshot(
                rootOrder: [.folder("folder")], folders: [folder], favoriteIDs: ["stable"]))

        _ = try state.reconcileCatalog([])
        #expect(state.records.isEmpty)
        #expect(state.retiredApplicationReferences.map(\.id) == ["stable"])

        let moved = ApplicationRecord(
            id: "new-path", name: "App Updated", bundleIdentifier: "com.example.app",
            url: URL(fileURLWithPath: "/synthetic/user/Applications/App.app"))
        _ = try state.reconcileCatalog([moved])
        #expect(state.records.map(\.id) == ["stable"])
        #expect(state.retiredApplicationReferences.isEmpty)
        #expect(state.folders.first?.applicationIDs == ["stable"])
        #expect(state.favoriteIDs == ["stable"])
    }

    @Test
    func retiredReferenceCapDropsOldestUnusedAndActiveRecordWins() throws {
        let retired = (0...(LibraryState.maximumRetiredApplicationReferences + 2)).map { index in
            record(String(format: "%04d", index), "Retired \(index)")
        }
        let active = record("0500", "Current")
        let state = try LibraryState(
            records: [active], organization: OrganizationSnapshot(),
            retiredApplicationReferences: retired)
        #expect(
            state.retiredApplicationReferences.count
                == LibraryState.maximumRetiredApplicationReferences)
        #expect(state.retiredApplicationReferences.first?.id == "0002")
        #expect(state.applicationReferences.first == active)
        #expect(state.applicationReferences.filter { $0.id == "0500" }.count == 1)
    }

    private var records: [ApplicationRecord] {
        [record("a", "Alpha"), record("b", "Beta"), record("c", "Charlie")]
    }
}

private func record(_ id: String, _ name: String) -> ApplicationRecord {
    ApplicationRecord(
        id: id, name: name, bundleIdentifier: "bundle.\(id)",
        url: URL(fileURLWithPath: "/\(name).app"))
}
