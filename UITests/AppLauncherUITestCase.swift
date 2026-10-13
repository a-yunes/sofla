import XCTest

@MainActor
class AppLauncherUITestCase: XCTestCase {
    private(set) var app = XCUIApplication()
    private(set) var stateDirectory = URL(
        fileURLWithPath: "/private/tmp/AppLauncherUITests-uninitialized",
        isDirectory: true
    )

    private var additionalLaunchArguments: [String] = []

    func startIsolatedTest(additionalArguments: [String] = []) throws {
        additionalLaunchArguments = additionalArguments
        continueAfterFailure = false
        stateDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppLauncherUITests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: stateDirectory,
            withIntermediateDirectories: true
        )
        launchApp()
    }

    func startIsolatedLoginPrewarmTest() throws {
        additionalLaunchArguments = ["--simulate-login-launch"]
        continueAfterFailure = false
        stateDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppLauncherUITests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: stateDirectory, withIntermediateDirectories: true)
        app = XCUIApplication()
        app.launchArguments =
            ["--ui-testing", "--state-directory", stateDirectory.path]
            + additionalLaunchArguments
        app.launch()
        XCTAssertTrue(app.menuBars.firstMatch.waitForExistence(timeout: 8))
        XCTAssertFalse(element("launcher.surface").waitForExistence(timeout: 2))
    }

    func finishIsolatedTest() {
        terminateAppAndWait()
        try? FileManager.default.removeItem(at: stateDirectory)
    }

    func launchApp() {
        app = XCUIApplication()
        app.launchArguments =
            ["--ui-testing", "--state-directory", stateDirectory.path]
            + additionalLaunchArguments
        app.launch()
        app.activate()
        let foreground = NSPredicate(
            format: "state == %d", XCUIApplication.State.runningForeground.rawValue)
        let foregroundExpectation = XCTNSPredicateExpectation(predicate: foreground, object: app)
        _ = XCTWaiter.wait(for: [foregroundExpectation], timeout: 5)
        if !element("launcher.surface").waitForExistence(timeout: 3) {
            showLauncherFromMenu()
        }
        XCTAssertTrue(
            element("launcher").waitForExistence(timeout: 8),
            "The launcher panel did not appear with its isolated test state."
        )
        XCTAssertTrue(
            element("launcher.surface").waitForExistence(timeout: 8),
            "The launcher content did not become accessible."
        )
        XCTAssertEqual(
            element("launcher.surface").label, "Sofla, Ready",
            "The launcher became accessible before presentation readiness completed."
        )
    }

    func relaunchApp() {
        terminateAppAndWait()
        launchApp()
    }

    func reopenLauncherFromMenu() {
        app.activate()
        showLauncherFromMenu()
        XCTAssertTrue(element("launcher.surface").waitForExistence(timeout: 12))
        XCTAssertEqual(element("launcher.surface").label, "Sofla, Ready")
    }

    private func showLauncherFromMenu() {
        let spacedAppMenu = app.menuBars.menuBarItems["Sofla"]
        let appMenu =
            spacedAppMenu.exists
            ? spacedAppMenu : app.menuBars.menuBarItems["AppLauncher"]
        XCTAssertTrue(appMenu.waitForExistence(timeout: 5))
        appMenu.click()
        let showLauncher = appMenu.menuItems["Show Launcher"]
        XCTAssertTrue(showLauncher.waitForExistence(timeout: 2))
        showLauncher.click()
    }

    func openSettings() {
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(app.windows["preferences"].waitForExistence(timeout: 5))
    }

    func closeSettings() {
        let settingsWindow = app.windows["preferences"]
        if settingsWindow.exists {
            settingsWindow.buttons[XCUIIdentifierCloseWindow].click()
        } else {
            app.typeKey("w", modifierFlags: .command)
        }
    }

    func replaceSearch(with text: String) {
        let search = app.searchFields["launcher.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.click()
        search.typeKey("a", modifierFlags: .command)
        search.typeText(text)
    }

    func rightClickApplication(_ identifier: String) {
        let application = app.buttons["app.\(identifier)"]
        XCTAssertTrue(application.waitForExistence(timeout: 3))
        application.rightClick()
    }

    func clickEmptyLauncherSpace(
        avoiding elements: [XCUIElement],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let surface = element("launcher.surface")
        XCTAssertTrue(
            surface.waitForExistence(timeout: 3),
            "The launcher surface was unavailable for the background click.",
            file: file,
            line: line
        )

        let blockedFrames = elements.filter(\.exists).map {
            $0.frame.insetBy(dx: -8, dy: -8)
        }
        let candidates = [
            CGVector(dx: 0.03, dy: 0.50),
            CGVector(dx: 0.97, dy: 0.50),
            CGVector(dx: 0.08, dy: 0.82),
            CGVector(dx: 0.92, dy: 0.82),
            CGVector(dx: 0.08, dy: 0.18),
            CGVector(dx: 0.92, dy: 0.18),
        ]
        let surfaceFrame = surface.frame
        guard
            let offset = candidates.first(where: { candidate in
                let point = CGPoint(
                    x: surfaceFrame.minX + surfaceFrame.width * candidate.dx,
                    y: surfaceFrame.minY + surfaceFrame.height * candidate.dy
                )
                return !blockedFrames.contains(where: { $0.contains(point) })
            })
        else {
            XCTFail(
                "No observed launcher coordinate was clear of the supplied accessibility frames.",
                file: file,
                line: line
            )
            return
        }

        surface.coordinate(withNormalizedOffset: offset).click()
    }

    func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    func waitForElementToDisappear(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    func waitForElementToBecomeSelected(
        _ element: XCUIElement, timeout: TimeInterval = 5
    ) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isSelected == true"), object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    func waitForStatePreference(
        named name: String,
        equalTo expectedValue: Bool,
        timeout: TimeInterval = 5
    ) -> Bool {
        let documentURL = stateDirectory.appendingPathComponent("library.json")
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let data = try? Data(contentsOf: documentURL),
                let document = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let preferences = document["preferences"] as? [String: Any],
                preferences[name] as? Bool == expectedValue
            {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline
        return false
    }

    func waitForPersistedFolder(
        containing applicationIDs: Set<String>,
        timeout: TimeInterval = 5
    ) -> Bool {
        let documentURL = stateDirectory.appendingPathComponent("library.json")
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let data = try? Data(contentsOf: documentURL),
                let document = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let organization = document["organization"] as? [String: Any],
                let folders = organization["folders"] as? [[String: Any]],
                folders.contains(where: { folder in
                    guard let values = folder["applicationIDs"] as? [String] else { return false }
                    return Set(values) == applicationIDs
                })
            {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline
        return false
    }

    func toggleIsOn(_ toggle: XCUIElement) -> Bool? {
        if let number = toggle.value as? NSNumber { return number.boolValue }
        if let value = toggle.value as? String {
            if value == "1" || value.localizedCaseInsensitiveCompare("on") == .orderedSame {
                return true
            }
            if value == "0" || value.localizedCaseInsensitiveCompare("off") == .orderedSame {
                return false
            }
        }
        return nil
    }

    func attachScreenshot(_ name: String) {
        guard ProcessInfo.processInfo.environment["APP_LAUNCHER_CAPTURE_SCREENSHOTS"] == "1"
        else { return }
        let screenshot: XCUIScreenshot
        if app.staticTexts["General"].exists, app.windows.firstMatch.exists {
            screenshot = app.windows.firstMatch.screenshot()
        } else if element("launcher").exists {
            screenshot = element("launcher").screenshot()
        } else if app.windows.firstMatch.exists {
            screenshot = app.windows.firstMatch.screenshot()
        } else {
            let unavailable = XCTAttachment(string: "No app window was visible for this state.")
            unavailable.name = "\(name) screenshot unavailable"
            unavailable.lifetime = .keepAlways
            add(unavailable)
            return
        }
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func attachStateFile(_ name: String) {
        let documentURL = stateDirectory.appendingPathComponent("library.json")
        let contents =
            (try? String(contentsOf: documentURL, encoding: .utf8))
            ?? "State file unavailable"
        let attachment = XCTAttachment(string: contents)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func terminateAppAndWait() {
        app.terminate()
        let deadline = Date().addingTimeInterval(5)
        while app.state != .notRunning, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
    }
}
