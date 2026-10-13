import XCTest

final class LauncherSearchAndLaunchUITests: AppLauncherUITestCase {
    @MainActor
    func testPresentationBenchmarkAcknowledgesAllSearchTransitions() throws {
        let report = FileManager.default.temporaryDirectory
            .appendingPathComponent("sofla-presentation-\(UUID().uuidString).json")
        defer {
            finishIsolatedTest()
            try? FileManager.default.removeItem(at: report)
        }
        try startIsolatedTest(additionalArguments: [
            "--benchmark-invocation", "--measure-invocation", "--benchmark-keep-running",
            "--benchmark-output", report.path,
        ])
        let completed = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in FileManager.default.fileExists(atPath: report.path) },
            object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 30), .completed)
        let result = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: report)) as? [String: Any])
        let searches = try XCTUnwrap(result["searchUpdateSamplesMilliseconds"] as? [Double])
        let invocations = try XCTUnwrap(result["warmSamplesMilliseconds"] as? [Double])
        XCTAssertEqual(result["searchRecordCount"] as? Int, 1_000)
        XCTAssertEqual(invocations.count, 20)
        XCTAssertEqual(searches.count, 100)
        XCTAssertTrue(searches.allSatisfy { $0.isFinite && $0 >= 0 })
        XCTAssertEqual(app.searchFields["launcher.search"].value as? String, "")
    }

    @MainActor
    func testArrowKeysNavigateSearchResultsWhileTypingAndReturnStillWork() throws {
        try startIsolatedTest()
        defer { finishIsolatedTest() }
        replaceSearch(with: "Cal")

        let search = app.searchFields["launcher.search"]
        let calculator = app.buttons["app.fixture-calculator"]
        let calendar = app.buttons["app.fixture-calendar"]
        XCTAssertTrue(calculator.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForElementToBecomeSelected(calculator))

        search.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertTrue(waitForElementToBecomeSelected(calendar))
        search.typeKey(.leftArrow, modifierFlags: [])
        XCTAssertTrue(waitForElementToBecomeSelected(calculator))
        search.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(waitForElementToBecomeSelected(calendar))
        search.typeKey(.upArrow, modifierFlags: [])
        XCTAssertTrue(waitForElementToBecomeSelected(calculator))
        XCTAssertEqual(search.value as? String, "Cal")

        search.typeText("c")
        XCTAssertEqual(search.value as? String, "Calc")
        XCTAssertTrue(waitForElementToBecomeSelected(calculator))
        XCTAssertFalse(calendar.exists)

        search.typeKey(.delete, modifierFlags: [])
        XCTAssertTrue(calendar.waitForExistence(timeout: 3))
        search.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertTrue(waitForElementToBecomeSelected(calendar))
        search.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForElementToDisappear(element("launcher.surface")))

        reopenLauncherFromMenu()
        app.buttons["collection.recents"].click()
        XCTAssertTrue(calendar.waitForExistence(timeout: 3))
        XCTAssertFalse(calculator.exists)
    }

    @MainActor
    func testArrowKeysWithNoSearchResultsPreserveTheInsertionPoint() throws {
        try startIsolatedTest()
        defer { finishIsolatedTest() }
        replaceSearch(with: "No Such Fixture")
        XCTAssertTrue(element("launcher.empty").waitForExistence(timeout: 3))

        let search = app.searchFields["launcher.search"]
        search.typeKey(.rightArrow, modifierFlags: [])
        search.typeKey(.leftArrow, modifierFlags: [])
        search.typeKey(.downArrow, modifierFlags: [])
        search.typeKey(.upArrow, modifierFlags: [])
        search.typeText("x")

        XCTAssertEqual(search.value as? String, "No Such Fixturex")
        XCTAssertTrue(element("launcher.empty").exists)
        search.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(app.buttons["app.fixture-notes"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testShowingAnAlreadyFocusedLauncherPreservesTheCurrentPage() throws {
        try startIsolatedTest(additionalArguments: ["--dense-ui-fixture"])
        defer { finishIsolatedTest() }

        let secondPage = app.buttons["Page 2"]
        XCTAssertTrue(secondPage.waitForExistence(timeout: 3))
        secondPage.click()
        XCTAssertTrue(waitForElementToBecomeSelected(secondPage))
        let applications = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "app."))
        let visibleApplicationIDs = applications.allElementsBoundByIndex.map(\.identifier)
        XCTAssertFalse(visibleApplicationIDs.isEmpty)

        reopenLauncherFromMenu()

        XCTAssertTrue(secondPage.isSelected)
        XCTAssertEqual(
            applications.allElementsBoundByIndex.map(\.identifier), visibleApplicationIDs,
            "Showing an already focused launcher reset or refreshed its visible page."
        )
    }

    @MainActor
    func testLoginLaunchPrewarmsWithoutPresentingTheLauncher() throws {
        try startIsolatedLoginPrewarmTest()
        defer { finishIsolatedTest() }

        reopenLauncherFromMenu()

        let surface = element("launcher.surface")
        XCTAssertTrue(surface.waitForExistence(timeout: 8))
        XCTAssertEqual(surface.label, "Sofla, Ready")
        app.typeText("N")
        XCTAssertEqual(app.searchFields["launcher.search"].value as? String, "N")
    }

    @MainActor
    func testEmptyBackgroundClickPreservesBrowsePageAndQuery() throws {
        try startIsolatedTest(additionalArguments: ["--dense-ui-fixture"])
        defer { finishIsolatedTest() }

        let secondPage = app.buttons["Page 2"]
        XCTAssertTrue(secondPage.waitForExistence(timeout: 3))
        secondPage.click()
        let applications = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "app."))
        let browsedApplicationIDs = applications.allElementsBoundByIndex.map(\.identifier)
        XCTAssertFalse(browsedApplicationIDs.isEmpty)

        clickEmptyLauncherSpace(avoiding: [element("launcher.grid")])

        XCTAssertTrue(element("launcher.surface").exists)
        XCTAssertEqual(
            applications.allElementsBoundByIndex.map(\.identifier),
            browsedApplicationIDs,
            "Clicking empty space changed the currently browsed page."
        )

        replaceSearch(with: "Cal")
        let calendar = app.buttons["app.fixture-calendar"]
        let calculator = app.buttons["app.fixture-calculator"]
        XCTAssertTrue(calendar.waitForExistence(timeout: 3))
        XCTAssertTrue(calculator.exists)

        clickEmptyLauncherSpace(avoiding: [element("launcher.grid")])

        XCTAssertTrue(element("launcher.surface").exists)
        XCTAssertEqual(app.searchFields["launcher.search"].value as? String, "Cal")
        XCTAssertTrue(calendar.exists)
        XCTAssertTrue(calculator.exists)
        attachScreenshot("Search preserved after empty background click")
    }

    @MainActor
    func testEscapeDismissesAndMenuCanReopenLauncher() throws {
        try startIsolatedTest()
        defer { finishIsolatedTest() }

        app.searchFields["launcher.search"].typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(
            waitForElementToDisappear(element("launcher.surface")),
            "Escape did not dismiss the launcher from its root state."
        )
        reopenLauncherFromMenu()
        XCTAssertTrue(app.searchFields["launcher.search"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testExactPrefixNoResultsAndEscapeRecovery() throws {
        try startIsolatedTest()
        defer { finishIsolatedTest() }
        replaceSearch(with: "Notes")
        XCTAssertTrue(app.buttons["app.fixture-notes"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["app.fixture-calendar"].exists)
        attachScreenshot("Search exact match")

        replaceSearch(with: "Cal")
        XCTAssertTrue(app.buttons["app.fixture-calendar"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["app.fixture-calculator"].exists)
        XCTAssertFalse(app.buttons["app.fixture-notes"].exists)
        attachScreenshot("Search prefix matches")

        replaceSearch(with: "No Such Fixture")
        XCTAssertTrue(element("launcher.empty").waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["No applications found"].exists)
        attachScreenshot("Search empty result")

        app.searchFields["launcher.search"].typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(app.buttons["app.fixture-notes"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.searchFields["launcher.search"].value as? String, "")
    }

    @MainActor
    func testFailedLaunchStaysVisibleAndSuccessfulLaunchDismisses() throws {
        try startIsolatedTest()
        defer { finishIsolatedTest() }
        replaceSearch(with: "Unavailable")
        app.buttons["app.fixture-unavailable"].click()

        let message = element("launcher.message")
        XCTAssertTrue(message.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Retry"].exists)
        XCTAssertTrue(element("launcher.surface").exists)
        attachScreenshot("Launch failure")

        replaceSearch(with: "Notes")
        app.buttons["app.fixture-notes"].click()
        XCTAssertTrue(waitForElementToDisappear(element("launcher.surface")))

        reopenLauncherFromMenu()
        XCTAssertFalse(element("launcher.message").exists)
        XCTAssertFalse(app.buttons["Retry"].exists)
        app.buttons["collection.recents"].click()
        XCTAssertFalse(app.staticTexts["Today"].exists)
        XCTAssertTrue(app.buttons["app.fixture-notes"].waitForExistence(timeout: 3))
        attachScreenshot("Recent application after successful launch")
    }
}
