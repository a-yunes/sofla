import AppKit
import Carbon.HIToolbox
import CoreGraphics
import XCTest

final class LauncherLiveAcceptanceTests: XCTestCase {
    @MainActor
    func testRealCatalogSearchAndCalculatorLaunch() throws {
        guard ProcessInfo.processInfo.environment["APP_LAUNCHER_LIVE_TESTS"] == "1" else {
            throw XCTSkip(
                "Run scripts/test-ui.sh --live to scan installed applications and launch Calculator."
            )
        }

        continueAfterFailure = false
        let stateDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "AppLauncherLiveAcceptance-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: stateDirectory, withIntermediateDirectories: true)
        // These journeys start after setup; onboarding has its own isolated UI coverage.
        try "1\n".write(
            to: stateDirectory.appendingPathComponent("setup-complete"),
            atomically: true, encoding: .utf8)

        let launcher = XCUIApplication()
        let calculator = XCUIApplication(bundleIdentifier: "com.apple.calculator")
        let calculatorPreviousState = calculator.state
        var calculatorLaunchRequested = false
        XCTAssertTrue(waitUntil(timeout: 10) { self.testLauncherProcesses().isEmpty })
        defer {
            launcher.terminate()
            _ = waitUntil(timeout: 5) { launcher.state == .notRunning }
            _ = waitUntil(timeout: 10) { self.testLauncherProcesses().isEmpty }
            if calculatorPreviousState == .notRunning, calculatorLaunchRequested,
                calculator.state != .notRunning
            {
                calculator.terminate()
                _ = waitUntil(timeout: 5) { calculator.state == .notRunning }
            }
            try? FileManager.default.removeItem(at: stateDirectory)
        }

        launcher.launchArguments = [
            "--live-verification", "--state-directory", stateDirectory.path,
            "--test-shortcut-key-code", String(kVK_F19),
            "--test-shortcut-modifiers", String(UInt32(cmdKey | optionKey | controlKey | shiftKey)),
        ]
        launcher.launchEnvironment["APP_LAUNCHER_TESTING"] = "0"
        launcher.launch()
        launcher.activate()
        let spacedAppMenu = launcher.menuBars.menuBarItems["Sofla"]
        let appMenu =
            spacedAppMenu.exists
            ? spacedAppMenu : launcher.menuBars.menuBarItems["AppLauncher"]
        XCTAssertTrue(appMenu.waitForExistence(timeout: 5))
        appMenu.click()
        let showLauncher = launcher.menuItems["Show Launcher"]
        XCTAssertTrue(showLauncher.waitForExistence(timeout: 3))
        showLauncher.click()

        let dialog = launcher.descendants(matching: .any).matching(identifier: "launcher")
            .firstMatch
        XCTAssertTrue(
            dialog.waitForExistence(timeout: 10),
            "The live launcher dialog did not appear."
        )
        let search = launcher.searchFields["launcher.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        let applicationButtons = dialog.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "app."))
        let loadedRealCatalog = waitUntil(timeout: 20) { applicationButtons.count > 10 }
        attach(dialog.screenshot(), named: "Real installed applications")
        attachCatalogDiagnostics(
            launcher: launcher,
            applicationButtons: applicationButtons,
            stateDirectory: stateDirectory
        )
        XCTAssertTrue(
            loadedRealCatalog,
            "The live catalog did not expose more than ten installed applications."
        )
        XCTAssertFalse(dialog.buttons["launcher.settings"].exists)
        XCTAssertTrue(
            dialog.buttons["Page 1"].isHittable,
            "The current-page control was clipped or unreachable with a full real-catalog grid."
        )

        search.click()
        search.typeText("Safari")
        let safariResult = dialog.buttons.matching(
            NSPredicate(format: "label == %@", "Safari")
        ).firstMatch
        XCTAssertTrue(
            safariResult.waitForExistence(timeout: 8),
            "Safari was not returned by the real application catalog search."
        )
        attach(dialog.screenshot(), named: "Safari search result")

        search.typeKey("a", modifierFlags: .command)
        search.typeText("Calculator")
        let calculatorResult = dialog.buttons.matching(
            NSPredicate(format: "label == %@", "Calculator")
        ).firstMatch
        XCTAssertTrue(
            calculatorResult.waitForExistence(timeout: 8),
            "Calculator was not returned by application-only search."
        )
        attach(dialog.screenshot(), named: "Calculator search result")

        calculatorLaunchRequested = true
        search.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(
            waitUntil(timeout: 10) { calculator.state == .runningForeground },
            "Calculator did not become the foreground application after Return."
        )
        XCTAssertTrue(
            waitUntil(timeout: 5) { !dialog.exists },
            "The launcher dialog remained visible after a successful launch."
        )
    }

    @MainActor
    func testDockHandoffDismissesLauncher() throws {
        guard ProcessInfo.processInfo.environment["APP_LAUNCHER_LIVE_TESTS"] == "1" else {
            throw XCTSkip(
                "Run scripts/test-ui.sh --live to exercise Dock handoff."
            )
        }

        continueAfterFailure = false
        let stateDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "AppLauncherShortcutAcceptance-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: stateDirectory, withIntermediateDirectories: true)
        // These journeys start after setup; onboarding has its own isolated UI coverage.
        try "1\n".write(
            to: stateDirectory.appendingPathComponent("setup-complete"),
            atomically: true, encoding: .utf8)

        let launcher = XCUIApplication()
        let calculator = XCUIApplication(bundleIdentifier: "com.apple.calculator")
        let calculatorPreviousState = calculator.state
        var calculatorLaunchRequested = false
        XCTAssertTrue(waitUntil(timeout: 10) { self.testLauncherProcesses().isEmpty })
        defer {
            launcher.terminate()
            _ = waitUntil(timeout: 5) { launcher.state == .notRunning }
            _ = waitUntil(timeout: 10) { self.testLauncherProcesses().isEmpty }
            if calculatorPreviousState == .notRunning, calculatorLaunchRequested,
                calculator.state != .notRunning
            {
                calculator.terminate()
                _ = waitUntil(timeout: 5) { calculator.state == .notRunning }
            }
            try? FileManager.default.removeItem(at: stateDirectory)
        }
        launcher.launchArguments = [
            "--live-verification", "--state-directory", stateDirectory.path,
            "--test-shortcut-key-code", String(kVK_F19),
            "--test-shortcut-modifiers", String(UInt32(cmdKey | optionKey | controlKey | shiftKey)),
        ]
        launcher.launchEnvironment["APP_LAUNCHER_TESTING"] = "0"

        if calculatorPreviousState == .notRunning {
            calculatorLaunchRequested = true
            calculator.launch()
            XCTAssertTrue(
                waitUntil(timeout: 5) { calculator.state != .notRunning },
                "Calculator did not start before Dock handoff verification."
            )
        } else {
            calculator.activate()
        }
        XCTAssertTrue(
            waitUntil(timeout: 5) { calculator.state == .runningForeground },
            "Calculator was not foreground before Sofla started."
        )

        launcher.launch()

        let dialog = launcher.descendants(matching: .any).matching(identifier: "launcher")
            .firstMatch
        XCTAssertTrue(dialog.waitForExistence(timeout: 10))
        let launcherPID = try XCTUnwrap(testLauncherPID())
        let calculatorPID = try XCTUnwrap(
            NSRunningApplication.runningApplications(
                withBundleIdentifier: "com.apple.calculator"
            ).first?.processIdentifier
        )
        let initialOrdering = waitForWindowOrdering(
            launcherPID: launcherPID,
            calculatorPID: calculatorPID,
            timeout: 5
        )
        attachWindowOrdering(initialOrdering)
        guard let initialOrdering else {
            XCTFail("CGWindowList did not expose both launcher and Calculator windows.")
            return
        }
        XCTAssertLessThan(
            initialOrdering.launcherIndex,
            initialOrdering.calculatorIndex,
            "Sofla was not ordered above Calculator when opened from Calculator."
        )
        attach(dialog.screenshot(), named: "Launcher ordered above Calculator")

        launcher.activate()
        let spacedAppMenu = launcher.menuBars.menuBarItems["Sofla"]
        let appMenu =
            spacedAppMenu.exists
            ? spacedAppMenu : launcher.menuBars.menuBarItems["AppLauncher"]
        XCTAssertTrue(appMenu.waitForExistence(timeout: 5))
        appMenu.click()
        let showLauncher = launcher.menuItems["Show Launcher"]
        XCTAssertTrue(showLauncher.waitForExistence(timeout: 3))
        showLauncher.click()
        XCTAssertTrue(dialog.waitForExistence(timeout: 5))

        let dock = XCUIApplication(bundleIdentifier: "com.apple.dock")
        let calculatorDockItem = dock.dockItems["Calculator"]
        XCTAssertTrue(
            calculatorDockItem.waitForExistence(timeout: 5),
            "Calculator was not available in the Dock for handoff verification."
        )
        calculatorDockItem.click()
        XCTAssertTrue(
            waitUntil(timeout: 5) { calculator.state == .runningForeground },
            "Clicking Calculator in the Dock did not make it foreground."
        )
        XCTAssertTrue(
            waitUntil(timeout: 5) { !dialog.exists },
            "Clicking Calculator in the Dock did not dismiss the visible launcher."
        )
    }

    @MainActor
    func testSettingsRetainsLauncherAndRestoresSearchFocus() throws {
        guard ProcessInfo.processInfo.environment["APP_LAUNCHER_LIVE_TESTS"] == "1" else {
            throw XCTSkip(
                "Run scripts/test-ui.sh --live to exercise Settings window ordering."
            )
        }

        continueAfterFailure = false
        let stateDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "AppLauncherSettingsAcceptance-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: stateDirectory, withIntermediateDirectories: true)
        // These journeys start after setup; onboarding has its own isolated UI coverage.
        try "1\n".write(
            to: stateDirectory.appendingPathComponent("setup-complete"),
            atomically: true, encoding: .utf8)
        let launcher = XCUIApplication()
        let calculator = XCUIApplication(bundleIdentifier: "com.apple.calculator")
        let calculatorPreviousState = calculator.state
        var calculatorLaunchRequested = false
        XCTAssertTrue(waitUntil(timeout: 10) { self.testLauncherProcesses().isEmpty })
        defer {
            launcher.terminate()
            _ = waitUntil(timeout: 5) { launcher.state == .notRunning }
            _ = waitUntil(timeout: 10) { self.testLauncherProcesses().isEmpty }
            if calculatorPreviousState == .notRunning, calculatorLaunchRequested,
                calculator.state != .notRunning
            {
                calculator.terminate()
                _ = waitUntil(timeout: 5) { calculator.state == .notRunning }
            }
            try? FileManager.default.removeItem(at: stateDirectory)
        }

        launcher.launchArguments = [
            "--live-verification", "--state-directory", stateDirectory.path,
            "--test-shortcut-key-code", String(kVK_F19),
            "--test-shortcut-modifiers", String(UInt32(cmdKey | optionKey | controlKey | shiftKey)),
        ]
        launcher.launchEnvironment["APP_LAUNCHER_TESTING"] = "0"
        launcher.launch()
        launcher.activate()

        let dialog = launcher.descendants(matching: .any).matching(identifier: "launcher")
            .firstMatch
        XCTAssertTrue(dialog.waitForExistence(timeout: 10))
        let search = launcher.searchFields["launcher.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.click()
        search.typeText("Calculator")
        XCTAssertEqual(search.value as? String, "Calculator")

        launcher.typeKey(",", modifierFlags: .command)
        let preferences = launcher.windows["preferences"]
        XCTAssertTrue(preferences.waitForExistence(timeout: 5))
        XCTAssertTrue(dialog.exists, "Opening Settings hid the retained launcher.")
        XCTAssertEqual(search.value as? String, "Calculator")

        let pid = try XCTUnwrap(testLauncherPID())
        let ordering = waitForSettingsAboveLauncher(pid: pid, timeout: 5)
        XCTAssertNotNil(ordering, "Settings was not observed above the retained launcher.")
        if let ordering {
            XCTAssertLessThan(ordering.settingsIndex, ordering.launcherIndex)
        }

        preferences.buttons[XCUIIdentifierCloseWindow].click()
        XCTAssertTrue(waitUntil(timeout: 5) { !preferences.exists })
        XCTAssertTrue(dialog.exists, "Closing Settings dismissed the retained launcher.")
        XCTAssertEqual(search.value as? String, "Calculator")
        search.typeText("x")
        XCTAssertEqual(search.value as? String, "Calculatorx")

        search.typeKey(.escape, modifierFlags: [])
        XCTAssertEqual(search.value as? String, "")
        search.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 5) { !dialog.exists })

        launcher.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(preferences.waitForExistence(timeout: 5))
        XCTAssertFalse(dialog.exists, "Standalone Settings unexpectedly revealed the launcher.")
        preferences.buttons[XCUIIdentifierCloseWindow].click()
        XCTAssertTrue(waitUntil(timeout: 5) { !preferences.exists })

        launcher.activate()
        let spacedAppMenu = launcher.menuBars.menuBarItems["Sofla"]
        let appMenu =
            spacedAppMenu.exists
            ? spacedAppMenu : launcher.menuBars.menuBarItems["AppLauncher"]
        XCTAssertTrue(appMenu.waitForExistence(timeout: 5))
        appMenu.click()
        launcher.menuItems["Show Launcher"].click()
        XCTAssertTrue(dialog.waitForExistence(timeout: 5))
        launcher.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(preferences.waitForExistence(timeout: 5))

        if calculatorPreviousState == .notRunning {
            calculatorLaunchRequested = true
            calculator.launch()
        } else {
            calculator.activate()
        }
        XCTAssertTrue(waitUntil(timeout: 5) { calculator.state == .runningForeground })
        XCTAssertTrue(
            waitUntil(timeout: 5) { !dialog.exists },
            "The launcher remained floating after another application became active."
        )
    }

    @MainActor
    private func waitUntil(
        timeout: TimeInterval,
        condition: () -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline
        return condition()
    }

    @MainActor
    private func waitForWindowOrdering(
        launcherPID: pid_t,
        calculatorPID: pid_t,
        timeout: TimeInterval
    ) -> WindowOrdering? {
        let deadline = Date().addingTimeInterval(timeout)
        var latestOrdering: WindowOrdering?
        repeat {
            if let ordering = currentWindowOrdering(
                launcherPID: launcherPID,
                calculatorPID: calculatorPID
            ) {
                latestOrdering = ordering
                if ordering.launcherIndex < ordering.calculatorIndex {
                    return ordering
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline
        return latestOrdering
    }

    private func currentWindowOrdering(
        launcherPID: pid_t,
        calculatorPID: pid_t
    ) -> WindowOrdering? {
        guard
            let windows = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID
            ) as? [[String: Any]]
        else { return nil }

        let launcherLevel = NSWindow.Level.floating.rawValue
        let calculatorLevel = NSWindow.Level.normal.rawValue
        guard
            let launcherIndex = windows.firstIndex(where: {
                windowOwnerPID($0) == launcherPID && windowLevel($0) == launcherLevel
            }),
            let calculatorIndex = windows.firstIndex(where: {
                windowOwnerPID($0) == calculatorPID && windowLevel($0) == calculatorLevel
            })
        else { return nil }

        return WindowOrdering(
            launcherIndex: launcherIndex,
            calculatorIndex: calculatorIndex,
            launcherLevel: launcherLevel,
            calculatorLevel: calculatorLevel
        )
    }

    @MainActor
    private func waitForSettingsAboveLauncher(
        pid: pid_t,
        timeout: TimeInterval
    ) -> SettingsWindowOrdering? {
        let deadline = Date().addingTimeInterval(timeout)
        var latest: SettingsWindowOrdering?
        repeat {
            if let windows = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
            ) as? [[String: Any]],
                let launcherIndex = windows.firstIndex(where: {
                    guard windowOwnerPID($0) == pid,
                        windowLevel($0) == NSWindow.Level.floating.rawValue,
                        let bounds = windowBounds($0)
                    else { return false }
                    return bounds.width > 900 || bounds.height > 700
                }),
                let settingsIndex = windows.firstIndex(where: {
                    guard windowOwnerPID($0) == pid, let bounds = windowBounds($0) else {
                        return false
                    }
                    return bounds.width >= 650 && bounds.width <= 900
                        && bounds.height >= 450 && bounds.height <= 700
                })
            {
                latest = SettingsWindowOrdering(
                    settingsIndex: settingsIndex, launcherIndex: launcherIndex)
                if settingsIndex < launcherIndex { return latest }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline
        return latest
    }

    private func windowOwnerPID(_ window: [String: Any]) -> pid_t? {
        (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
    }

    private func testLauncherPID() -> pid_t? {
        testLauncherProcesses().first?.processIdentifier
    }

    private func testLauncherProcesses() -> [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: "app.sofla.launcher")
            .filter {
                $0.bundleURL?.path.contains(
                    "/build/DerivedData/Build/Products/Debug/Sofla.app"
                ) == true
            }
    }

    private func windowLevel(_ window: [String: Any]) -> Int? {
        (window[kCGWindowLayer as String] as? NSNumber)?.intValue
    }

    private func windowBounds(_ window: [String: Any]) -> CGRect? {
        guard let dictionary = window[kCGWindowBounds as String] as? NSDictionary else {
            return nil
        }
        return CGRect(dictionaryRepresentation: dictionary)
    }

    private func attachWindowOrdering(_ ordering: WindowOrdering?) {
        let details: String
        if let ordering {
            details = """
                CGWindowList front-to-back launcher index: \(ordering.launcherIndex)
                CGWindowList front-to-back Calculator index: \(ordering.calculatorIndex)
                Launcher window level: \(ordering.launcherLevel)
                Calculator window level: \(ordering.calculatorLevel)
                """
        } else {
            details = "CGWindowList did not report Sofla above Calculator."
        }
        let attachment = XCTAttachment(string: details)
        attachment.name = "Launcher and Calculator window ordering"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func attach(_ screenshot: @autoclosure () -> XCUIScreenshot, named name: String) {
        guard ProcessInfo.processInfo.environment["APP_LAUNCHER_CAPTURE_SCREENSHOTS"] == "1"
        else { return }
        let attachment = XCTAttachment(screenshot: screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func attachCatalogDiagnostics(
        launcher: XCUIApplication,
        applicationButtons: XCUIElementQuery,
        stateDirectory: URL
    ) {
        let labels = applicationButtons.allElementsBoundByIndex.map { $0.label }
        let catalogURL = stateDirectory.appendingPathComponent("catalog-cache.json")
        let cachedCount: String
        if let data = try? Data(contentsOf: catalogURL),
            let catalog = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let records = catalog["records"] as? [[String: Any]]
        {
            cachedCount = String(records.count)
        } else {
            cachedCount = "unavailable"
        }
        let message = launcher.staticTexts.matching(identifier: "launcher.message").firstMatch
        let details = """
            Visible application count: \(applicationButtons.count)
            Visible labels: \(labels.joined(separator: ", "))
            Cached catalog record count: \(cachedCount)
            Launcher message: \(message.exists ? message.label : "none")
            """
        let attachment = XCTAttachment(string: details)
        attachment.name = "Live catalog diagnostics"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private struct WindowOrdering {
    let launcherIndex: Int
    let calculatorIndex: Int
    let launcherLevel: Int
    let calculatorLevel: Int
}

private struct SettingsWindowOrdering {
    let settingsIndex: Int
    let launcherIndex: Int
}
