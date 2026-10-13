import Foundation
import Testing

@testable import AppLauncher

@MainActor
struct OnboardingTests {
    @MainActor private final class FakeLogin {
        var status = LoginService.Status.notRegistered
        var fail = false
        var registrations = 0
        var settingsOpened = 0
        enum Failure: Error { case denied }
        func service() -> LoginService {
            LoginService(
                readStatus: { self.status },
                register: {
                    self.registrations += 1
                    if self.fail { throw Failure.denied }
                    self.status = .requiresApproval
                },
                unregister: {
                    if self.fail { throw Failure.denied }
                    self.status = .notRegistered
                },
                openSettings: { self.settingsOpened += 1 })
        }
    }

    @Test func optionalStartupNeedsNoPermissionAndCompletionPersists() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let login = FakeLogin()
        let marker = directory.appendingPathComponent("complete")
        let setup = OnboardingModel(login: login.service(), completionURL: marker)
        #expect(!setup.isComplete)
        #expect(setup.canFinish)
        #expect(setup.finish())
        #expect(login.registrations == 0)
        #expect(OnboardingModel(login: login.service(), completionURL: marker).isComplete)
    }

    @Test func registrationWaitsForActualApprovalAndRechecksAtFinish() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let login = FakeLogin()
        let setup = OnboardingModel(
            login: login.service(), completionURL: directory.appendingPathComponent("complete"))
        setup.setLogin(true)
        #expect(setup.login.status == .requiresApproval)
        #expect(!setup.canFinish)
        #expect(!setup.finish())
        #expect(!setup.isComplete)
        setup.login.openSystemSettings()
        #expect(login.settingsOpened == 1)
        login.status = .enabled
        setup.refresh()
        #expect(setup.canFinish)
        login.status = .requiresApproval
        #expect(!setup.finish())
        login.status = .enabled
        #expect(setup.finish())
    }

    @Test func pendingApprovalCanBeExplicitlySkippedButFailedOptOutIsNotHidden() {
        let login = FakeLogin()
        login.status = .requiresApproval
        let setup = OnboardingModel(
            login: login.service(), completionURL: URL(fileURLWithPath: "/unused"))
        #expect(setup.wantsLogin)
        login.fail = true
        setup.setLogin(false)
        #expect(setup.wantsLogin)
        #expect(!setup.canFinish)
        #expect(setup.error != nil)
        login.fail = false
        setup.setLogin(false)
        #expect(!setup.wantsLogin)
        #expect(setup.canFinish)
        #expect(setup.login.status == .notRegistered)
    }

    @Test func failedRegistrationAndFailedPersistenceStayIncomplete() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data().write(to: directory)
        let login = FakeLogin()
        login.fail = true
        let setup = OnboardingModel(
            login: login.service(), completionURL: directory.appendingPathComponent("complete"))
        setup.setLogin(true)
        #expect(!setup.canFinish)
        #expect(setup.error != nil)
        setup.setLogin(false)
        #expect(!setup.finish())
        #expect(!setup.isComplete)
        #expect(setup.error != nil)
    }
}
