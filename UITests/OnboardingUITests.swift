import XCTest

@MainActor
final class OnboardingUITests: XCTestCase {
    func testSetupCanSkipStartupAndDoesNotRepeatAfterCompletion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        let app = XCUIApplication()
        defer {
            app.terminate()
            try? FileManager.default.removeItem(at: directory)
        }
        app.launchArguments = [
            "--ui-testing", "--onboarding-testing", "--state-directory", directory.path,
        ]
        app.launch()
        let welcome = app.windows["onboarding"]
        XCTAssertTrue(welcome.waitForExistence(timeout: 10))
        let attachment = XCTAttachment(screenshot: welcome.screenshot())
        attachment.name = "Welcome to Sofla"
        attachment.lifetime = .keepAlways
        add(attachment)
        welcome.buttons["onboarding.continue"].click()
        XCTAssertTrue(welcome.buttons["onboarding.shortcut"].waitForExistence(timeout: 3))
        welcome.buttons["onboarding.continue"].click()
        XCTAssertTrue(welcome.switches["onboarding.login"].waitForExistence(timeout: 3))
        let startup = XCTAttachment(screenshot: welcome.screenshot())
        startup.name = "Optional startup"
        startup.lifetime = .keepAlways
        add(startup)
        welcome.buttons["onboarding.continue"].click()
        XCTAssertTrue(
            app.descendants(matching: .any)["launcher.surface"].waitForExistence(timeout: 10))
        app.terminate()
        app.launch()
        XCTAssertTrue(
            app.descendants(matching: .any)["launcher.surface"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.windows["onboarding"].exists)
    }

    func testUnapprovedStartupOffersRetryAndExplicitSkip() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        let app = XCUIApplication()
        defer {
            app.terminate()
            try? FileManager.default.removeItem(at: directory)
        }
        app.launchArguments = [
            "--ui-testing", "--onboarding-testing", "--state-directory", directory.path,
        ]
        app.launch()
        let welcome = app.windows["onboarding"]
        XCTAssertTrue(welcome.waitForExistence(timeout: 10))
        welcome.buttons["onboarding.continue"].click()
        welcome.buttons["onboarding.continue"].click()
        welcome.switches["onboarding.login"].click()
        XCTAssertFalse(welcome.buttons["onboarding.continue"].isEnabled)
        XCTAssertTrue(welcome.buttons["onboarding.loginApproval"].exists)
        welcome.buttons["onboarding.recheck"].click()
        XCTAssertFalse(welcome.buttons["onboarding.continue"].isEnabled)
        welcome.buttons["onboarding.skipLogin"].click()
        XCTAssertTrue(welcome.buttons["onboarding.continue"].isEnabled)
        welcome.buttons["onboarding.continue"].click()
        XCTAssertTrue(
            app.descendants(matching: .any)["launcher.surface"].waitForExistence(timeout: 10))
    }
}
