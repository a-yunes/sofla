import Foundation
import LauncherCore
import Testing

@testable import AppLauncher

@MainActor
struct ActivationHistoryTests {
    @Test(arguments: [false, true])
    func excludedUnchangedHistoryDoesNotSaveOrInvalidateReadiness(disabled: Bool) throws {
        let model = try makeModel()
        model.library.preferences.recordsRecents = !disabled
        model.library.preferences.recentsScope = .launcher
        let generation = model.readinessGeneration

        model.recordActivation("app", source: .workspace)

        #expect(model.library.recents.isEmpty)
        #expect(model.saveTask == nil)
        #expect(model.readinessGeneration == generation)
    }

    @Test
    func realHistoryChangeSavesWithoutInvalidatingAllApps() async throws {
        let model = try makeModel()
        let generation = model.readinessGeneration
        model.recordActivation("app", source: .launcher)
        #expect(model.library.recents.map(\.applicationID) == ["app"])
        #expect(model.saveTask != nil)
        #expect(model.readinessGeneration == generation)
        model.saveTask?.cancel()
        await model.saveTask?.value
    }

    @Test
    func excludedEventStillPrunesExpiredHistoryAndRefreshesRecents() async throws {
        let model = try makeModel()
        try model.library.apply(
            .replaceRecents([
                RecentApplication(applicationID: "app", accessedAt: Date(timeIntervalSince1970: 0))
            ]))
        model.library.preferences.recordsRecents = false
        model.collection = .recents
        let generation = model.readinessGeneration

        model.recordActivation("app", source: .workspace)

        #expect(model.library.recents.isEmpty)
        #expect(model.items.isEmpty)
        #expect(model.readinessGeneration > generation)
        #expect(model.saveTask != nil)
        model.saveTask?.cancel()
        await model.saveTask?.value
    }

    private func makeModel() throws -> LauncherModel {
        let record = ApplicationRecord(
            id: "app", name: "App", bundleIdentifier: "fixture.app",
            url: URL(fileURLWithPath: "/synthetic/App.app"))
        let model = LauncherModel(
            library: try LibraryState(records: [record]),
            dataDirectory: FileManager.default.temporaryDirectory.appending(
                path: UUID().uuidString),
            isTesting: true, now: { Date(timeIntervalSince1970: 200 * 86_400) })
        model.isReady = true
        return model
    }
}
