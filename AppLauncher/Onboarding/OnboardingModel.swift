import Foundation
import Observation

@MainActor @Observable
final class OnboardingModel {
    enum Step: Int, CaseIterable {
        case welcome, shortcut, startup
    }

    var step = Step.welcome
    private(set) var wantsLogin: Bool
    private(set) var isComplete: Bool
    var error: String?
    let login: LoginService
    private let completionURL: URL

    init(login: LoginService, completionURL: URL) {
        self.login = login
        self.completionURL = completionURL
        wantsLogin = login.status == .enabled || login.status == .requiresApproval
        isComplete = (try? String(contentsOf: completionURL, encoding: .utf8)) == "1\n"
    }

    var canFinish: Bool { !wantsLogin || login.status == .enabled }

    func setLogin(_ enabled: Bool) {
        wantsLogin = enabled
        error = nil
        login.refresh()
        if !enabled, login.status == .notRegistered || login.status == .notFound { return }
        do {
            try login.setEnabledByUser(enabled)
        } catch {
            self.error = "Couldn’t update Open at Login. \(error.localizedDescription)"
            // A failed opt-out must not silently leave an unwanted login item registered.
            if !enabled {
                wantsLogin = login.status != .notRegistered && login.status != .notFound
            }
        }
    }

    func refresh() { login.refresh() }

    @discardableResult
    func finish() -> Bool {
        refresh()
        guard canFinish else { return false }
        do {
            try FileManager.default.createDirectory(
                at: completionURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "1\n".write(to: completionURL, atomically: true, encoding: .utf8)
            isComplete = true
            return true
        } catch {
            self.error = "Couldn’t save setup. \(error.localizedDescription)"
            return false
        }
    }
}
