import XCTest

final class LauncherOrganizationUITests: AppLauncherUITestCase {
    @MainActor
    func testEmptyBackgroundClickPreservesOpenFolder() throws {
        try startIsolatedTest()
        defer { finishIsolatedTest() }

        rightClickApplication("fixture-notes")
        let moveToFolder = app.menuItems["Move to Folder"]
        XCTAssertTrue(moveToFolder.waitForExistence(timeout: 2))
        moveToFolder.hover()
        let newFolder = app.menuItems["New folder with"]
        XCTAssertTrue(newFolder.waitForExistence(timeout: 2))
        newFolder.hover()
        let calendarPartner = app.menuItems["Calendar"]
        XCTAssertTrue(calendarPartner.waitForExistence(timeout: 2))
        calendarPartner.click()
        XCTAssertTrue(app.textFields["dialog.text"].waitForExistence(timeout: 5))
        app.sheets.buttons["Create"].click()

        let folder = app.otherElements["launcher.folder"]
        XCTAssertTrue(folder.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["app.fixture-notes"].exists)
        XCTAssertTrue(app.buttons["app.fixture-calendar"].exists)

        clickEmptyLauncherSpace(avoiding: [folder])

        XCTAssertTrue(folder.exists, "Clicking empty space closed the open folder.")
        XCTAssertTrue(app.buttons["app.fixture-notes"].exists)
        XCTAssertTrue(app.buttons["app.fixture-calendar"].exists)
        attachScreenshot("Folder preserved after empty background click")
    }

    @MainActor
    func testFavoriteHideAndSettingsRecovery() throws {
        try startIsolatedTest()
        defer { finishIsolatedTest() }
        rightClickApplication("fixture-notes")
        let favorite = app.menuItems["Add to Favorites"]
        XCTAssertTrue(favorite.waitForExistence(timeout: 2))
        favorite.click()

        app.buttons["collection.favorites"].click()
        XCTAssertTrue(app.buttons["app.fixture-notes"].waitForExistence(timeout: 3))
        attachScreenshot("Favorites collection")

        rightClickApplication("fixture-notes")
        let hide = app.menuItems["Hide App"]
        XCTAssertTrue(hide.waitForExistence(timeout: 2))
        hide.click()
        XCTAssertTrue(element("launcher.empty").waitForExistence(timeout: 3))

        openSettings()
        element("preferences.section.searchAndApps").click()
        let hiddenFilter = app.radioButtons["Hidden"]
        XCTAssertTrue(hiddenFilter.waitForExistence(timeout: 3))
        hiddenFilter.click()
        let unhide = app.buttons["Unhide Notes"]
        app.windows["preferences"].scrollViews.element(boundBy: 1)
            .scroll(byDeltaX: 0, deltaY: -260)
        XCTAssertTrue(unhide.waitForExistence(timeout: 3))
        attachScreenshot("Hidden application recovery")
        unhide.click()
        closeSettings()

        reopenLauncherFromMenu()
        app.buttons["collection.all"].click()
        XCTAssertTrue(app.buttons["app.fixture-notes"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testContextMenuCreatesFolderAndFolderCanBeRenamed() throws {
        try startIsolatedTest()
        defer { finishIsolatedTest() }
        let notes = app.buttons["app.fixture-notes"]
        XCTAssertTrue(notes.waitForExistence(timeout: 3))

        notes.rightClick()
        let moveToFolder = app.menuItems["Move to Folder"]
        XCTAssertTrue(moveToFolder.waitForExistence(timeout: 2))
        moveToFolder.hover()
        let newFolder = app.menuItems["New folder with"]
        XCTAssertTrue(newFolder.waitForExistence(timeout: 2))
        newFolder.hover()
        let calendarPartner = app.menuItems["Calendar"]
        XCTAssertTrue(calendarPartner.waitForExistence(timeout: 2))
        calendarPartner.click()

        let createNameField = app.textFields["dialog.text"]
        XCTAssertTrue(createNameField.waitForExistence(timeout: 3))
        app.sheets.buttons["Create"].click()
        XCTAssertTrue(element("launcher.folder").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["app.fixture-notes"].exists)
        XCTAssertTrue(app.buttons["app.fixture-calendar"].exists)
        attachScreenshot("New folder")

        app.buttons["New Folder"].click()
        let nameField = app.textFields["dialog.text"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.click()
        nameField.typeKey("a", modifierFlags: .command)
        nameField.typeText("Planning")
        app.sheets.buttons["Save"].click()

        XCTAssertTrue(app.buttons["Planning"].waitForExistence(timeout: 3))
        attachScreenshot("Renamed folder")
        let folderBack = app.buttons.matching(
            NSPredicate(format: "identifier == %@ AND label == %@", "launcher.folder", "All apps")
        ).firstMatch
        XCTAssertTrue(folderBack.waitForExistence(timeout: 3))
        folderBack.click()
        XCTAssertTrue(
            app.buttons.matching(
                NSPredicate(
                    format: "identifier BEGINSWITH %@", "folder."
                )
            ).firstMatch.waitForExistence(timeout: 3))
    }

    @MainActor
    func testDragCreatesFolder() throws {
        try startIsolatedTest()
        defer { finishIsolatedTest() }
        let notes = app.buttons["app.fixture-notes"]
        let calendar = app.buttons["app.fixture-calendar"]
        XCTAssertTrue(notes.waitForExistence(timeout: 3))
        XCTAssertTrue(calendar.exists)
        XCTAssertTrue(notes.isHittable)
        XCTAssertTrue(calendar.isHittable)

        XCTContext.runActivity(named: "Drag geometry") { activity in
            let geometry = XCTAttachment(
                string: "Notes frame: \(notes.frame); Calendar frame: \(calendar.frame)"
            )
            geometry.name = "Drag source and destination frames"
            geometry.lifetime = .keepAlways
            activity.add(geometry)
        }
        attachScreenshot("Before folder drag")
        let source = notes.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        let destination = calendar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        source.click(forDuration: 0.8, thenDragTo: destination)
        let persistedFolder = waitForPersistedFolder(
            containing: ["fixture-notes", "fixture-calendar"],
            timeout: 5
        )
        attachStateFile("State after folder drag")
        attachScreenshot("After folder drag")
        XCTAssertTrue(
            element("launcher.folder").waitForExistence(timeout: 3),
            "The folder created by the macOS click-drag did not remain open."
        )
        XCTAssertTrue(app.buttons["app.fixture-notes"].exists)
        XCTAssertTrue(app.buttons["app.fixture-calendar"].exists)
        XCTAssertTrue(
            persistedFolder,
            "The dragged application identities were not persisted in the folder."
        )
    }

    @MainActor
    func testDragToFavoritesPreservesAllAppsPlacementAndCollection() throws {
        try startIsolatedTest()
        defer { finishIsolatedTest() }
        let notes = app.buttons["app.fixture-notes"]
        let favorites = app.buttons["collection.favorites"]
        XCTAssertTrue(notes.waitForExistence(timeout: 3))
        XCTAssertTrue(favorites.waitForExistence(timeout: 3))
        let originalFrame = notes.frame

        let source = notes.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        let destination = favorites.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        source.click(forDuration: 0.8, thenDragTo: destination)

        XCTAssertTrue(app.buttons["collection.all"].isSelected)
        XCTAssertTrue(notes.waitForExistence(timeout: 3))
        XCTAssertEqual(notes.frame, originalFrame)
        XCTAssertTrue(element("launcher.dropConfirmation").waitForExistence(timeout: 3))

        app.buttons["collection.favorites"].click()
        XCTAssertTrue(notes.waitForExistence(timeout: 3))
        attachScreenshot("Favorites drop confirmation")
    }

    @MainActor
    func testMoveToTrashEligibilityAndConfirmationCancellationUseDisposableFixture() throws {
        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppLauncherTrashUITest-\(UUID().uuidString)")
        let disposable = fixtureRoot.appendingPathComponent("Disposable.app")
        try FileManager.default.createDirectory(at: disposable, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        try startIsolatedTest(
            additionalArguments: ["--trash-fixture-path", disposable.path])
        defer { finishIsolatedTest() }

        rightClickApplication("fixture-notes")
        XCTAssertFalse(app.menuItems["Move to Trash..."].exists)
        app.typeKey(.escape, modifierFlags: [])

        rightClickApplication("fixture-disposable")
        let moveToTrash = app.menuItems["Move to Trash..."]
        XCTAssertTrue(moveToTrash.waitForExistence(timeout: 2))
        moveToTrash.click()
        let confirmationPath = app.sheets.descendants(matching: .any).matching(
            NSPredicate(
                format: "label CONTAINS %@ OR value CONTAINS %@",
                disposable.path,
                disposable.path
            )
        ).firstMatch
        XCTAssertTrue(confirmationPath.waitForExistence(timeout: 3))
        app.sheets.buttons["Cancel"].click()

        XCTAssertTrue(FileManager.default.fileExists(atPath: disposable.path))
        XCTAssertTrue(app.buttons["app.fixture-disposable"].exists)
    }
}
