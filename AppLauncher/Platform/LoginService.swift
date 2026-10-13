import Observation
import ServiceManagement

/// Reflects the operating system's login-item state, including pending approval.
@MainActor
@Observable
public final class LoginService {
    public enum Status: Sendable, Equatable {
        case notRegistered
        case enabled
        case requiresApproval
        case notFound
        case unknown
    }

    public private(set) var status: Status
    private let readStatus: () -> Status
    private let register: () throws -> Void
    private let unregister: () throws -> Void
    private let openSettings: () -> Void

    public convenience init() {
        self.init(
            readStatus: { Self.map(SMAppService.mainApp.status) },
            register: { try SMAppService.mainApp.register() },
            unregister: { try SMAppService.mainApp.unregister() },
            openSettings: { SMAppService.openSystemSettingsLoginItems() }
        )
    }

    init(
        readStatus: @escaping () -> Status,
        register: @escaping () throws -> Void,
        unregister: @escaping () throws -> Void,
        openSettings: @escaping () -> Void
    ) {
        self.readStatus = readStatus
        self.register = register
        self.unregister = unregister
        self.openSettings = openSettings
        status = readStatus()
    }

    static func fixture() -> LoginService {
        LoginService(readStatus: { .notRegistered }, register: {}, unregister: {}, openSettings: {})
    }

    public func refresh() { status = readStatus() }

    /// Registration success alone does not establish that macOS approved the login item.
    public func setEnabledByUser(_ enabled: Bool) throws {
        defer { refresh() }
        if enabled {
            try register()
        } else {
            try unregister()
        }
    }

    public func openSystemSettings() { openSettings() }

    private static func map(_ status: SMAppService.Status) -> Status {
        switch status {
        case .notRegistered: .notRegistered
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .notFound
        @unknown default: .unknown
        }
    }
}
