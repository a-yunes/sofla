import AppKit
import Carbon.HIToolbox
import CoreGraphics
import XCTest

final class LauncherShortcutLiveAcceptanceTests: XCTestCase {
    @MainActor
    func testExclusiveShortcutOpensLauncherFromCalculator() throws {
        guard ProcessInfo.processInfo.environment["APP_LAUNCHER_LIVE_TESTS"] == "1" else {
            throw XCTSkip(
                "Run scripts/test-ui.sh --live --shortcut to exercise the exclusive shortcut.")
        }

        try XCTSkipUnless(
            CGPreflightPostEventAccess(),
            "Global shortcut injection requires event-posting access for the test runner. Verify the physical shortcut separately if unavailable."
        )
        continueAfterFailure = false
        let stateDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "AppLauncherExclusiveShortcut-\(UUID().uuidString)", isDirectory: true)
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
        defer {
            launcher.terminate()
            _ = waitUntil(timeout: 5) { launcher.state == .notRunning }
            if calculatorPreviousState == .notRunning, calculatorLaunchRequested,
                calculator.state != .notRunning
            {
                calculator.terminate()
                _ = waitUntil(timeout: 5) { calculator.state == .notRunning }
            }
            try? FileManager.default.removeItem(at: stateDirectory)
        }

        let modifiers = UInt32(cmdKey | optionKey | controlKey | shiftKey)
        launcher.launchArguments = [
            "--live-verification",
            "--state-directory", stateDirectory.path,
            "--test-shortcut-key-code", String(kVK_F19),
            "--test-shortcut-modifiers", String(modifiers),
        ]
        launcher.launchEnvironment["APP_LAUNCHER_TESTING"] = "0"
        launcher.launch()
        launcher.activate()

        let launcherWindow = launcher.descendants(matching: .any)
            .matching(identifier: "launcher").firstMatch
        XCTAssertTrue(launcherWindow.waitForExistence(timeout: 10))
        if calculatorPreviousState == .notRunning {
            calculatorLaunchRequested = true
            calculator.launch()
            XCTAssertTrue(waitUntil(timeout: 5) { calculator.state != .notRunning })
        }

        launcher.activate()
        let spacedAppMenu = launcher.menuBars.menuBarItems["Sofla"]
        let appMenu =
            spacedAppMenu.exists
            ? spacedAppMenu : launcher.menuBars.menuBarItems["AppLauncher"]
        XCTAssertTrue(appMenu.waitForExistence(timeout: 5))
        appMenu.click()
        launcher.menuItems["Show Launcher"].click()
        XCTAssertTrue(launcherWindow.waitForExistence(timeout: 5))

        let calculatorDockItem = XCUIApplication(bundleIdentifier: "com.apple.dock")
            .dockItems["Calculator"]
        XCTAssertTrue(calculatorDockItem.waitForExistence(timeout: 5))
        calculatorDockItem.click()
        XCTAssertTrue(waitUntil(timeout: 5) { calculator.state == .runningForeground })
        XCTAssertTrue(waitUntil(timeout: 5) { !launcherWindow.exists })

        // Element-scoped key synthesis can stall when a global shortcut changes the active app.
        let keyDown = try XCTUnwrap(
            CGEvent(
                keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_F19), keyDown: true))
        let keyUp = try XCTUnwrap(
            CGEvent(
                keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_F19), keyDown: false))
        keyDown.flags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
        keyUp.flags = keyDown.flags
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        XCTAssertTrue(
            launcherWindow.waitForExistence(timeout: 5),
            "The exclusive F19 test shortcut did not open Sofla from Calculator."
        )
        XCTAssertTrue(waitUntil(timeout: 5) { launcher.state == .runningForeground })
        launcher.typeKey("n", modifierFlags: [])
        XCTAssertTrue(
            waitUntil(timeout: 3) {
                launcher.searchFields["launcher.search"].value as? String == "n"
            },
            "The shortcut-opened launcher did not own immediate typing focus."
        )
    }

    @MainActor
    private func waitUntil(timeout: TimeInterval, condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline
        return condition()
    }
}
