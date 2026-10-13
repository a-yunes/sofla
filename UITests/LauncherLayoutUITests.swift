import XCTest

final class LauncherLayoutUITests: AppLauncherUITestCase {
    @MainActor
    func testLastPageHoverScreenshot() throws {
        try startIsolatedTest(additionalArguments: ["--dense-ui-fixture"])
        defer { finishIsolatedTest() }

        let secondPage = app.buttons["Page 2"]
        XCTAssertTrue(secondPage.waitForExistence(timeout: 3))
        secondPage.click()
        XCTAssertTrue(waitForElementToBecomeSelected(secondPage))
        let firstItem = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "app.")
        ).firstMatch
        XCTAssertTrue(firstItem.waitForExistence(timeout: 3))
        firstItem.hover()
        attachScreenshot("Last page hover with stable grid geometry")
    }

    @MainActor
    func testCollectionsSearchAndPagesKeepTheSameGridGeometry() throws {
        try startIsolatedTest(additionalArguments: ["--dense-ui-fixture"])
        defer { finishIsolatedTest() }
        let notes = app.buttons["app.fixture-notes"]
        XCTAssertTrue(notes.waitForExistence(timeout: 3))
        let originalFrame = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "app.")
        ).firstMatch.frame
        let searchFrame = app.searchFields["launcher.search"].frame
        let collections = element("launcher.collections")
        XCTAssertTrue(collections.waitForExistence(timeout: 3))
        let tabsFrame = collections.frame
        XCTAssertFalse(app.buttons["launcher.settings"].exists)
        attachGeometryState("All Apps baseline", item: notes)

        rightClickApplication("fixture-notes")
        app.menuItems["Add to Favorites"].click()
        app.buttons["collection.favorites"].click()
        XCTAssertTrue(notes.waitForExistence(timeout: 3))
        attachGeometryState("Favorites", item: notes)
        assertSameFrame(notes.frame, originalFrame)

        replaceSearch(with: "Notes")
        XCTAssertFalse(app.staticTexts["1 application"].exists)
        for collection in ["all", "favorites", "recents"] {
            XCTAssertTrue(app.buttons["collection.\(collection)"].exists)
        }
        attachGeometryState("Search", item: notes)
        assertSameFrame(notes.frame, originalFrame)
        assertSameFrame(app.searchFields["launcher.search"].frame, searchFrame)
        assertSameFrame(collections.frame, tabsFrame)
        attachScreenshot("Stable search grid and persistent collection tabs")

        notes.click()
        XCTAssertTrue(waitForElementToDisappear(element("launcher.surface")))
        reopenLauncherFromMenu()
        app.buttons["collection.recents"].click()
        XCTAssertTrue(notes.waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Today"].exists)
        attachGeometryState("Recents", item: notes)
        assertSameFrame(notes.frame, originalFrame)
        attachScreenshot("Recents use the same icon slots")

        app.buttons["collection.all"].click()
        let secondPage = app.buttons["Page 2"]
        XCTAssertTrue(secondPage.waitForExistence(timeout: 3))
        secondPage.click()
        XCTAssertTrue(waitForElementToBecomeSelected(secondPage))
        let firstItem = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "app.")
        ).firstMatch
        XCTAssertTrue(firstItem.waitForExistence(timeout: 3))
        attachGeometryState("Page 2", item: firstItem)
        assertSameFrame(firstItem.frame, originalFrame)
        assertSameFrame(app.searchFields["launcher.search"].frame, searchFrame)
        firstItem.hover()
        attachScreenshot("Last page hover with stable grid geometry")
    }

    @MainActor
    func testOptionalCollectionCapsuleKeepsHeaderAndGridGeometryStable() throws {
        try startIsolatedTest()
        defer { finishIsolatedTest() }
        let notes = app.buttons["app.fixture-notes"]
        XCTAssertTrue(notes.waitForExistence(timeout: 3))
        let itemFrame = notes.frame
        let searchFrame = app.searchFields["launcher.search"].frame
        let gridFrame = element("launcher.grid").frame

        openSettings()
        element("preferences.section.layout").click()
        let favorites = app.switches["preferences.showsFavorites"]
        let recents = app.switches["preferences.showsRecents"]
        XCTAssertTrue(favorites.waitForExistence(timeout: 3))
        XCTAssertTrue(recents.exists)
        if toggleIsOn(favorites) == true { favorites.click() }
        if toggleIsOn(recents) == true { recents.click() }
        closeSettings()

        XCTAssertTrue(app.searchFields["launcher.search"].waitForExistence(timeout: 3))
        XCTAssertFalse(element("launcher.collections").exists)
        assertSameFrame(app.searchFields["launcher.search"].frame, searchFrame)
        assertSameFrame(element("launcher.grid").frame, gridFrame)
        assertSameFrame(notes.frame, itemFrame)

        openSettings()
        element("preferences.section.layout").click()
        app.switches["preferences.showsFavorites"].click()
        closeSettings()
        XCTAssertTrue(element("launcher.collections").waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["collection.all"].exists)
        XCTAssertTrue(app.buttons["collection.favorites"].exists)
        XCTAssertFalse(app.buttons["collection.recents"].exists)
        assertSameFrame(app.searchFields["launcher.search"].frame, searchFrame)
        assertSameFrame(element("launcher.grid").frame, gridFrame)

        openSettings()
        element("preferences.section.layout").click()
        app.switches["preferences.showsRecents"].click()
        closeSettings()
        XCTAssertTrue(app.buttons["collection.favorites"].exists)
        XCTAssertTrue(app.buttons["collection.recents"].exists)
        assertSameFrame(app.searchFields["launcher.search"].frame, searchFrame)
        assertSameFrame(element("launcher.grid").frame, gridFrame)

        rightClickApplication("fixture-notes")
        XCTAssertFalse(app.menuItems["Arrange Apps…"].exists)
        app.typeKey(.escape, modifierFlags: [])
    }

    @MainActor
    func testAlphabeticalRestorationIsAvailableFromNativeMenuAndSettings() throws {
        try startIsolatedTest()
        defer { finishIsolatedTest() }
        XCTAssertTrue(app.buttons["app.fixture-notes"].waitForExistence(timeout: 3))
        let applications = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "app."))
        XCTAssertEqual(applications.firstMatch.label, "Calculator")

        rightClickApplication("fixture-notes")
        app.menuItems["Move to beginning"].click()
        XCTAssertEqual(applications.firstMatch.label, "Notes")

        app.menuBars.menuBarItems["Edit"].click()
        app.menuItems["Restore Alphabetical Order"].click()
        XCTAssertEqual(applications.firstMatch.label, "Calculator")
        app.typeKey("z", modifierFlags: .command)
        XCTAssertEqual(applications.firstMatch.label, "Notes")

        openSettings()
        element("preferences.section.layout").click()
        let restore = app.buttons["preferences.restoreAlphabeticalOrder"]
        XCTAssertTrue(restore.waitForExistence(timeout: 3))
        restore.click()
        closeSettings()
        reopenLauncherFromMenu()
        XCTAssertEqual(applications.firstMatch.label, "Calculator")
    }

    @MainActor
    private func assertSameFrame(
        _ actual: CGRect, _ expected: CGRect, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(actual.minX, expected.minX, accuracy: 1, file: file, line: line)
        XCTAssertEqual(actual.minY, expected.minY, accuracy: 1, file: file, line: line)
        XCTAssertEqual(actual.width, expected.width, accuracy: 1, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: 1, file: file, line: line)
    }

    @MainActor
    private func attachGeometryState(_ name: String, item: XCUIElement) {
        let details = """
            Item: \(item.frame)
            Search: \(app.searchFields["launcher.search"].frame)
            Tabs: \(element("launcher.collections").frame)
            Grid: \(element("launcher.grid").frame)
            Launcher: \(element("launcher").frame)
            """
        let attachment = XCTAttachment(string: details)
        attachment.name = "\(name) geometry"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

}
