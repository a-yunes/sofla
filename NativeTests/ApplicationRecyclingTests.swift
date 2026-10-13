import AppKit
import LauncherCore
import Testing

@testable import AppLauncher

@Suite
@MainActor
struct ApplicationRecyclingTests {
    @Test
    func workspaceAdapterForwardsTrashMapping() async throws {
        let source = URL(fileURLWithPath: "/private/tmp/Example.app")
        let trashed = URL(fileURLWithPath: "/.Trashes/501/Example.app")
        let recycler = WorkspaceApplicationRecycler { receivedURL in
            #expect(receivedURL == source)
            return [source: trashed]
        }

        let mapping = try await recycler.recycle(source)

        #expect(mapping == [source: trashed])
    }

    @Test
    func workspaceAdapterPreservesTheOriginalError() async {
        let source = URL(fileURLWithPath: "/private/tmp/Example.app")
        let recycler = WorkspaceApplicationRecycler { _ in
            throw TestRecycleError.denied
        }

        await #expect(throws: TestRecycleError.denied) {
            try await recycler.recycle(source)
        }
    }

    @Test
    func modelSuccessRequestsReconciliationWithoutChangingOrganization() async throws {
        let fixture = try RecyclingModelFixture()
        defer { fixture.remove() }
        let trashed = fixture.root.appendingPathComponent("Trash/Example.app")
        let recycler = WorkspaceApplicationRecycler { url in [url: trashed] }
        let model = try fixture.model(recycler: recycler)
        let organization = model.library.organization
        var refreshRequested = false
        model.onCatalogRefresh = { refreshRequested = true }

        model.performMoveToTrash(fixture.application)
        await model.recycleTask?.value

        #expect(refreshRequested)
        #expect(model.library.organization == organization)
        #expect(model.message?.contains("Moved Example to Trash") == true)
    }

    @Test
    func modelFailurePreservesOrganizationAndReportsTheOriginalError() async throws {
        let fixture = try RecyclingModelFixture()
        defer { fixture.remove() }
        let recycler = WorkspaceApplicationRecycler { _ in throw TestRecycleError.denied }
        let model = try fixture.model(recycler: recycler)
        let organization = model.library.organization

        model.performMoveToTrash(fixture.application)
        await model.recycleTask?.value

        #expect(model.library.organization == organization)
        #expect(model.message?.contains("denied") == true)
    }
}

private enum TestRecycleError: LocalizedError, Equatable {
    case denied

    var errorDescription: String? { "Recycling denied" }
}

@MainActor
private final class RecyclingModelFixture {
    let root: URL
    let application: ApplicationRecord

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppLauncherRecycleModel-\(UUID().uuidString)")
        let url = root.appendingPathComponent("Example.app")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        application = ApplicationRecord(
            id: "example", name: "Example", bundleIdentifier: "example.app", url: url)
    }

    func model(recycler: any ApplicationRecycling) throws -> LauncherModel {
        let model = LauncherModel(
            library: try LibraryState(records: [application]),
            dataDirectory: root.appendingPathComponent("State"),
            isTesting: true,
            recycler: recycler
        )
        model.isReady = true
        return model
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
