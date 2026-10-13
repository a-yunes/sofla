import Foundation
import LauncherCore
import LauncherInfrastructure
import Testing

@testable import AppLauncher

@Suite
@MainActor
struct LauncherModelIntegrationTests {
    @Test
    func initialLoadingStateStartsRealDiscoveryWithoutAnExistingScanTask() async throws {
        let fixture = try ModelFixture()
        let applications = fixture.dataDirectory.appending(path: "Applications")
        let contents = applications.appending(path: "Example.app/Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let metadata = try PropertyListSerialization.data(
            fromPropertyList: [
                "CFBundleName": "Example", "CFBundleIdentifier": "example.discovery",
                "CFBundlePackageType": "APPL",
            ], format: .xml, options: 0)
        try metadata.write(to: contents.appending(path: "Info.plist"))
        let model = LauncherModel(
            library: try LibraryState(), dataDirectory: fixture.dataDirectory,
            isTesting: false,
            standardApplicationRoots: [
                ApplicationScanRoot(id: "fixture", url: applications, kind: .standard)
            ])
        #expect(model.isScanning)
        #expect(model.scanTask == nil)
        model.catalogMessage = "A previous scan was incomplete."

        await model.start()
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while model.isScanning, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(!model.isScanning)
        #expect(model.library.records.map(\.name) == ["Example"])
        #expect(model.items.count == 1)
        #expect(model.catalogMessage == nil)
        model.changes.stop()
        await fixture.finish(models: [model])
    }

    @Test
    func dismissingLaunchFailurePreservesUnderlyingRecoveryMessage() async throws {
        let fixture = try ModelFixture()
        let model = try await fixture.startedModel()
        model.lastFailedLaunch = model.record("fixture-notes")
        model.launchFailure = "Could not open Notes."
        model.message = "The application folder is unavailable."
        model.catalogMessage = "Some application details could not be read."

        model.dismissMessage()

        #expect(model.launchFailure == nil)
        #expect(model.lastFailedLaunch == nil)
        #expect(model.message == "The application folder is unavailable.")
        model.dismissMessage()
        #expect(model.message == nil)
        #expect(model.catalogMessage != nil)
        model.dismissMessage()
        #expect(model.catalogMessage == nil)
        await fixture.finish(models: [model])
    }

    @Test
    func mutationsAreIgnoredBeforeInitialLoad() async throws {
        let fixture = try ModelFixture()
        let model = try fixture.makeModel()
        let initialLibrary = model.library

        model.execute(
            .restore(OrganizationSnapshot(favoriteIDs: ["not-loaded"])),
            name: "Premature change")
        model.updatePreferences { $0.showsKeyboardHints.toggle() }

        #expect(model.library == initialLibrary)
        #expect(model.message == nil)
        await fixture.finish(models: [model])
    }

    @Test
    func searchIsGlobalWhenFavoritesAreSelected() async throws {
        let fixture = try ModelFixture()
        let model = try await fixture.startedModel()
        let notesID = "fixture-notes"
        let terminalID = "fixture-terminal"
        #expect(model.record(notesID)?.name == "Notes")
        #expect(model.record(terminalID)?.name == "Terminal")
        model.execute(.setFavorite(applicationID: notesID, isFavorite: true), name: "Favorite")
        model.collection = .favorites
        #expect(model.items == [.application(notesID)])

        model.query = "Terminal"

        #expect(model.items == [.application(terminalID)])
        #expect(model.items.allSatisfy { if case .application = $0 { true } else { false } })
        await fixture.finish(models: [model])
    }

    @Test
    func hidingApplicationInvalidatesCachedSearchResults() async throws {
        let fixture = try ModelFixture()
        let model = try await fixture.startedModel()
        let notesID = "fixture-notes"
        #expect(model.record(notesID)?.name == "Notes")
        model.query = "Notes"
        #expect(model.items == [.application(notesID)])

        model.execute(.setHidden(applicationID: notesID, isHidden: true), name: "Hide")

        #expect(model.items.isEmpty)
        #expect(model.library.hiddenIDs.contains(notesID))
        await fixture.finish(models: [model])
    }

    @Test
    func commandUndoAndRedoDoNotDisturbFavorites() async throws {
        let fixture = try ModelFixture()
        let model = try await fixture.startedModel()
        let notesID = "fixture-notes"
        #expect(model.record(notesID)?.name == "Notes")
        model.execute(.setFavorite(applicationID: notesID, isFavorite: true), name: "Favorite")
        model.undoManager.removeAllActions()

        model.execute(.setHidden(applicationID: notesID, isHidden: true), name: "Hide")
        #expect(model.library.favoriteIDs == [notesID])
        #expect(model.library.hiddenIDs.contains(notesID))

        model.undoManager.undo()
        #expect(model.library.favoriteIDs == [notesID])
        #expect(!model.library.hiddenIDs.contains(notesID))

        model.undoManager.redo()
        #expect(model.library.favoriteIDs == [notesID])
        #expect(model.library.hiddenIDs.contains(notesID))
        await fixture.finish(models: [model])
    }

    @Test
    func favoritesDropIsIndependentIdempotentAndRejectsFolders() async throws {
        let fixture = try ModelFixture()
        let model = try await fixture.startedModel()
        let notesID = "fixture-notes"
        let originalRoot = model.library.rootOrder
        model.collection = .all

        #expect(model.dropOnFavorites(.application(notesID)))
        #expect(model.library.favoriteIDs == [notesID])
        #expect(model.library.rootOrder == originalRoot)
        #expect(model.collection == .all)

        #expect(model.dropOnFavorites(.application(notesID)))
        #expect(model.library.favoriteIDs == [notesID])
        #expect(!model.dropOnFavorites(.folder("not-a-drag-source")))
        #expect(model.library.favoriteIDs == [notesID])
        #expect(model.library.rootOrder == originalRoot)
        await fixture.finish(models: [model])
    }

    @Test
    func cancellingDragClearsPresentationWithoutMutatingOrganization() async throws {
        let fixture = try ModelFixture()
        let model = try await fixture.startedModel()
        let organization = model.library.organization
        model.draggedItem = .application("fixture-notes")
        model.dropTarget = .applicationMerge("fixture-calendar")

        model.escape()

        #expect(model.draggedItem == nil)
        #expect(model.dropTarget == nil)
        #expect(model.library.organization == organization)
        await fixture.finish(models: [model])
    }

    @Test
    func preferenceCallbackFailureRestoresPreviousPreferences() async throws {
        let fixture = try ModelFixture()
        let model = try await fixture.startedModel()
        let original = model.preferences
        model.onPreferencesChanged = { throw ModelTestError.preferenceCallback }

        model.updatePreferences { $0.showsKeyboardHints.toggle() }

        #expect(model.preferences == original)
        #expect(model.message?.contains("Could not apply this preference") == true)
        model.onPreferencesChanged = nil
        await fixture.finish(models: [model])
    }

    @Test
    func restoreDefaultsRollsBackWithoutChangingShortcutOrOrganizationOnFailure() async throws {
        let fixture = try ModelFixture()
        let model = try await fixture.startedModel()
        model.execute(
            .setFavorite(applicationID: "fixture-notes", isFavorite: true), name: "Favorite")
        model.updatePreferences { $0.showsFavorites = false }
        let original = model.library
        model.onPreferencesChanged = { throw ModelTestError.preferenceCallback }

        model.restoreDefaultSettings()

        #expect(model.library == original)
        #expect(model.preferences.shortcut == original.preferences.shortcut)
        #expect(model.library.organization == original.organization)
        model.onPreferencesChanged = nil
        await fixture.finish(models: [model])
    }

    @Test
    func restoreDefaultsPreservesRecentsEvenWhenNewDefaultsWouldPruneThem() async throws {
        let fixture = try ModelFixture()
        let model = try await fixture.startedModel()
        let oldRecent = RecentApplication(
            applicationID: "fixture-notes",
            accessedAt: Date().addingTimeInterval(-100 * 86_400)
        )
        try model.library.apply(.replaceRecents([oldRecent]))
        model.updatePreferences { $0.retentionDays = 365 }

        model.restoreDefaultSettings()

        #expect(model.preferences.retentionDays == 30)
        #expect(model.library.recents == [oldRecent])
        await fixture.finish(models: [model])
    }

    @Test
    func loweringMaximumRecentsPrunesImmediately() async throws {
        let fixture = try ModelFixture()
        let model = try await fixture.startedModel()
        let now = Date()
        try model.library.apply(
            .replaceRecents([
                RecentApplication(
                    applicationID: "fixture-notes", accessedAt: now),
                RecentApplication(
                    applicationID: "fixture-calendar",
                    accessedAt: now.addingTimeInterval(-1)),
                RecentApplication(
                    applicationID: "fixture-terminal",
                    accessedAt: now.addingTimeInterval(-2)),
            ]))

        model.updatePreferences { $0.maximumRecentsCount = 1 }

        #expect(model.library.recents.map(\.applicationID) == ["fixture-notes"])
        #expect(model.preferences.maximumRecentsCount == 1)
        await fixture.finish(models: [model])
    }

    @Test
    func recoveryLockPreventsOrganizationAndPreferenceChanges() async throws {
        let fixture = try ModelFixture()
        let model = try await fixture.startedModel()
        let notesID = "fixture-notes"
        #expect(model.record(notesID)?.name == "Notes")
        let original = model.library
        model.recoveryLocked = true

        model.execute(.setFavorite(applicationID: notesID, isFavorite: true), name: "Favorite")
        model.updatePreferences { $0.showsKeyboardHints.toggle() }

        #expect(model.library == original)
        #expect(model.message?.contains("Restore or import") == true)
        model.recoveryLocked = false
        await fixture.finish(models: [model])
    }

    @Test
    func flushedStateLoadsIntoReconstructedModel() async throws {
        let fixture = try ModelFixture()
        let first = try await fixture.startedModel()
        let notesID = "fixture-notes"
        let calendarID = "fixture-calendar"
        #expect(first.record(notesID)?.name == "Notes")
        #expect(first.record(calendarID)?.name == "Calendar")
        first.execute(.setFavorite(applicationID: notesID, isFavorite: true), name: "Favorite")
        first.execute(.setHidden(applicationID: calendarID, isHidden: true), name: "Hide")
        first.updatePreferences { $0.showsKeyboardHints = true }

        let flushed = await first.flush()
        #expect(flushed)
        await fixture.settle(first, flush: false)
        let reconstructed = try await fixture.startedModel()

        #expect(reconstructed.library.favoriteIDs == [notesID])
        #expect(reconstructed.library.hiddenIDs.contains(calendarID))
        #expect(reconstructed.preferences.showsKeyboardHints)
        await fixture.settle(reconstructed)
        await fixture.settle(first, flush: false)
        fixture.remove()
    }
}

private enum ModelTestError: Error {
    case preferenceCallback
}

@MainActor
private final class ModelFixture {
    let dataDirectory: URL

    init() throws {
        dataDirectory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: dataDirectory, withIntermediateDirectories: true)
    }

    func makeModel() throws -> LauncherModel {
        LauncherModel(
            library: try LibraryState(), dataDirectory: dataDirectory, isTesting: true)
    }

    func startedModel() async throws -> LauncherModel {
        let model = try makeModel()
        await model.start()
        return model
    }

    func settle(_ model: LauncherModel, flush: Bool = true) async {
        if flush, model.isReady, !model.recoveryLocked {
            _ = await model.flush()
        }
        let pendingSave = model.saveTask
        pendingSave?.cancel()
        await pendingSave?.value
        model.saveTask = nil
        model.scanRequestTask?.cancel()
        model.scanTask?.cancel()
        model.dragPageTask?.cancel()
        model.undoManager.removeAllActions()
    }

    func finish(models: [LauncherModel]) async {
        for model in models {
            await settle(model)
        }
        try? FileManager.default.removeItem(at: dataDirectory)
    }

    func remove() {
        try? FileManager.default.removeItem(at: dataDirectory)
    }
}
