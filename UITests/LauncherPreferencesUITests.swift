import XCTest

final class LauncherPreferencesUITests: AppLauncherUITestCase {
    @MainActor
    func testUpdateControlsAreOptionalAndTestPreferencesStayIsolated() throws {
        try startIsolatedTest()
        defer { finishIsolatedTest() }
        openSettings()
        element("preferences.section.updates").click()
        let checks = app.switches["preferences.updateChecks"]
        let downloads = app.switches["preferences.updateDownloads"]
        XCTAssertTrue(checks.waitForExistence(timeout: 3))
        XCTAssertEqual(toggleIsOn(checks), false)
        XCTAssertFalse(downloads.isEnabled)
        checks.click()
        XCTAssertTrue(downloads.isEnabled)
        downloads.click()
        XCTAssertEqual(toggleIsOn(downloads), true)
        app.buttons["preferences.checkForUpdates"].click()
        XCTAssertTrue(element("preferences.lastUpdateCheck").waitForExistence(timeout: 3))
        let attachment = XCTAttachment(screenshot: app.windows["preferences"].screenshot())
        attachment.name = "Software update settings"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.terminate()
        app.launch()
        openSettings()
        element("preferences.section.updates").click()
        XCTAssertEqual(toggleIsOn(app.switches["preferences.updateChecks"]), false)
    }

    @MainActor
    func testFixedSidebarAndPreferenceSectionsExposeFeedbackControls() throws {
        try startIsolatedTest()
        defer { finishIsolatedTest() }

        openSettings()
        let settings = app.windows["preferences"]
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        XCTAssertGreaterThanOrEqual(settings.frame.width, 700)
        XCTAssertGreaterThanOrEqual(settings.frame.height, 500)
        XCTAssertFalse(app.toolbars.buttons["Sidebar"].exists)
        XCTAssertFalse(app.buttons["Show Sidebar"].exists)
        XCTAssertTrue(element("launcher.surface").exists)

        element("preferences.section.general").click()
        XCTAssertTrue(app.buttons["preferences.shortcutReset"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.switches["preferences.recordsRecents"].exists)
        XCTAssertTrue(app.staticTexts["preferences.recentsLocalOnly"].exists)
        XCTAssertTrue(app.steppers["preferences.maximumRecentsCount"].exists)

        element("preferences.section.layout").click()
        XCTAssertTrue(
            app.popUpButtons["preferences.pageSwipeSensitivity"].waitForExistence(timeout: 3)
        )
        XCTAssertTrue(app.popUpButtons["preferences.dockIconAppearance"].exists)
        XCTAssertTrue(app.buttons["preferences.restoreDefaults"].exists)

        element("preferences.section.searchAndApps").click()
        let applicationSearch = app.textFields["preferences.applicationSearch"]
        XCTAssertTrue(applicationSearch.waitForExistence(timeout: 3))
        XCTAssertTrue(element("preferences.applicationFilter").exists)
        applicationSearch.click()
        applicationSearch.typeText("Notes")
        app.windows["preferences"].scrollViews.element(boundBy: 1)
            .scroll(byDeltaX: 0, deltaY: -260)
        XCTAssertTrue(app.staticTexts["Aliases: None"].waitForExistence(timeout: 3))
        attachScreenshot("Fixed settings sidebar and feedback controls")
    }

    @MainActor
    func testRestoreDefaultsPreservesShortcutAndOrganization() throws {
        try startIsolatedTest()
        defer { finishIsolatedTest() }

        rightClickApplication("fixture-notes")
        app.menuItems["Add to Favorites"].click()
        openSettings()
        let shortcutBefore = persistedPreferenceValue(named: "shortcut")
        let layout = element("preferences.section.layout")
        layout.click()
        let favoritesToggle = app.switches["preferences.showsFavorites"]
        XCTAssertTrue(favoritesToggle.waitForExistence(timeout: 3))
        favoritesToggle.click()
        XCTAssertEqual(toggleIsOn(favoritesToggle), false)

        let restoreDefaults = app.buttons["preferences.restoreDefaults"]
        XCTAssertTrue(restoreDefaults.waitForExistence(timeout: 3))
        restoreDefaults.click()
        XCTAssertTrue(
            waitForStatePreference(named: "showsFavorites", equalTo: true),
            "Restore Default Settings did not restore the app-owned preference."
        )
        XCTAssertEqual(persistedPreferenceValue(named: "shortcut"), shortcutBefore)

        closeSettings()
        XCTAssertTrue(app.searchFields["launcher.search"].waitForExistence(timeout: 3))
        app.buttons["collection.favorites"].click()
        XCTAssertTrue(app.buttons["app.fixture-notes"].waitForExistence(timeout: 3))
        attachScreenshot("Restore defaults preserves organization")
    }

    @MainActor
    func testHiddenFilterProvidesExplicitUnhideAction() throws {
        try startIsolatedTest()
        defer { finishIsolatedTest() }

        rightClickApplication("fixture-notes")
        app.menuItems["Hide App"].click()
        openSettings()
        element("preferences.section.searchAndApps").click()
        let hidden = app.radioButtons["Hidden"]
        XCTAssertTrue(hidden.waitForExistence(timeout: 3))
        hidden.click()

        let unhide = app.buttons["preferences.unhide.fixture-notes"]
        app.windows["preferences"].scrollViews.element(boundBy: 1)
            .scroll(byDeltaX: 0, deltaY: -260)
        XCTAssertTrue(unhide.waitForExistence(timeout: 3))
        unhide.click()
        closeSettings()
        XCTAssertTrue(app.buttons["collection.all"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["app.fixture-notes"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testLayoutPreferencePersistsAcrossIsolatedRelaunch() throws {
        try startIsolatedTest()
        defer { finishIsolatedTest() }
        openSettings()
        element("preferences.section.layout").click()

        let favoritesToggle = app.switches["preferences.showsFavorites"]
        XCTAssertTrue(favoritesToggle.waitForExistence(timeout: 3))
        XCTAssertEqual(toggleIsOn(favoritesToggle), true)
        favoritesToggle.click()
        XCTAssertEqual(toggleIsOn(favoritesToggle), false)
        attachScreenshot("Layout preference changed")

        XCTAssertTrue(
            waitForStatePreference(named: "showsFavorites", equalTo: false),
            "The preference was not persisted before relaunch."
        )
        relaunchApp()
        XCTAssertFalse(app.buttons["collection.favorites"].exists)

        openSettings()
        element("preferences.section.layout").click()
        let relaunchedToggle = app.switches["preferences.showsFavorites"]
        XCTAssertTrue(relaunchedToggle.waitForExistence(timeout: 3))
        XCTAssertEqual(toggleIsOn(relaunchedToggle), false)
        attachScreenshot("Persisted layout preference after relaunch")
    }

    private func persistedPreferenceValue(named name: String) -> AnyHashable? {
        let url = stateDirectory.appendingPathComponent("library.json")
        guard let data = try? Data(contentsOf: url),
            let document = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let preferences = document["preferences"] as? [String: Any]
        else { return nil }
        if let value = preferences[name] as? String { return AnyHashable(value) }
        if let value = preferences[name] as? [String: Any] {
            guard
                let data = try? JSONSerialization.data(
                    withJSONObject: value, options: [.sortedKeys]),
                let string = String(data: data, encoding: .utf8)
            else { return nil }
            return AnyHashable(string)
        }
        return nil
    }
}
