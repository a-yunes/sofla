import AppKit

@MainActor
protocol ApplicationLaunching {
    func open(_ url: URL) async throws
}

struct WorkspaceApplicationLauncher: ApplicationLaunching {
    func open(_ url: URL) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = false
        configuration.allowsRunningApplicationSubstitution = false
        _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }
}

/// UI tests can exercise focus/dismissal without opening any installed application.
struct FixtureApplicationLauncher: ApplicationLaunching {
    func open(_ url: URL) async throws {
        if url.lastPathComponent == "Unavailable.app" {
            throw CocoaError(.fileNoSuchFile)
        }
    }
}
