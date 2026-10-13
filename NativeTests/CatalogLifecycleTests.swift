import Foundation
import LauncherCore
import LauncherInfrastructure
import Testing

@testable import AppLauncher

@MainActor
struct CatalogLifecycleTests {
    @Test
    func refreshesDuringScanCoalesceAndPersistLatestResult() async throws {
        try await withModel { model, scanner in
            model.refreshCatalog()
            try #require(await scanner.started.wait())
            let initial = try #require(model.scanTask)
            model.refreshCatalog()
            model.refreshCatalog()
            model.refreshCatalog()
            await scanner.finish(0, records: [self.record("first")])
            await initial.value
            try #require(await scanner.started.wait(for: 2))
            let refresh = try #require(model.scanTask)
            await scanner.finish(1, records: [self.record("latest")])
            await refresh.value

            #expect(await scanner.callCount == 2)
            #expect(!model.isScanning)
            #expect(model.scanTask == nil)
            #expect(model.library.records.map(\.name) == ["latest"])
            #expect(try await model.store.loadCatalog()?.records == model.library.records)
        }
    }

    @Test
    func changedRootsRejectLateResultsAndPreserveCurrentOrganization() async throws {
        try await withModel { model, scanner in
            model.refreshCatalog()
            try #require(await scanner.started.wait())
            let oldTask = try #require(model.scanTask)
            let existing = self.record("existing")
            _ = try model.library.reconcileCatalog([existing])
            model.refreshItems()
            model.library.preferences.customApplicationFolders = [
                URL(fileURLWithPath: "/synthetic/new-root", isDirectory: true)
            ]
            model.restartCatalogForChangedRoots()
            model.changes.stop()
            try #require(await scanner.started.wait(for: 2))
            let newTask = try #require(model.scanTask)
            model.execute(
                .setFavorite(applicationID: existing.id, isFavorite: true), name: "Favorite")
            await scanner.finish(1, records: [existing, self.record("new")])
            await newTask.value
            await scanner.finish(0, records: [self.record("stale")])
            await oldTask.value

            #expect(model.library.records.map(\.name) == ["existing", "new"])
            #expect(model.library.favoriteIDs == [existing.id])
            #expect(!model.isScanning)
            #expect(try await model.store.loadCatalog()?.records == model.library.records)
        }
    }

    @Test(arguments: [false, true])
    func failedOrCancelledScanClearsBusyStateAndAllowsRetry(cancelled: Bool) async throws {
        try await withModel { model, scanner in
            model.refreshCatalog()
            try #require(await scanner.started.wait())
            let first = try #require(model.scanTask)
            await scanner.fail(0, cancelled: cancelled)
            await first.value
            #expect(!model.isScanning)
            #expect(model.scanTask == nil)
            #expect(model.catalogMessage != nil || cancelled)
            model.refreshCatalog()
            try #require(await scanner.started.wait(for: 2))
            let second = try #require(model.scanTask)
            await scanner.finish(1, records: [self.record("recovered")])
            await second.value
            #expect(model.library.records.map(\.name) == ["recovered"])
            #expect(model.catalogMessage == nil)
        }
    }

    @Test
    func warmReadinessDoesNotWaitForSuspendedRefresh() async throws {
        try await withModel { model, scanner in
            model.hasCompletedInitialScan = true
            model.refreshCatalog()
            try #require(await scanner.started.wait())
            let readiness = await model.prepareForPresentation { .ready }
            #expect(readiness == .ready)
            #expect(model.isScanning)
            #expect(await scanner.callCount == 1)
        }
    }

    @Test
    func initialReadinessWaitsForTheFirstScanButNotItsQueuedRefresh() async throws {
        try await withModel { model, scanner in
            model.refreshCatalog()
            try #require(await scanner.started.wait())
            model.refreshCatalog()
            let preparationStarted = TestSignal()
            let readiness = Task {
                await preparationStarted.advance()
                return await model.prepareForPresentation { .ready }
            }
            try #require(await preparationStarted.wait())
            #expect(!model.hasCompletedInitialScan)
            await scanner.finish(0, records: [])
            try #require(await scanner.started.wait(for: 2))
            #expect(await readiness.value == .ready)
            #expect(model.isScanning)
        }
    }

    private func record(_ name: String) -> ApplicationRecord {
        ApplicationRecord(
            id: name, name: name, bundleIdentifier: "fixture.\(name)",
            url: URL(fileURLWithPath: "/synthetic/\(name).app"))
    }

    private func withModel(
        _ operation: @MainActor (LauncherModel, ControlledScanner) async throws -> Void
    ) async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let scanner = ControlledScanner()
        let model = LauncherModel(
            library: try LibraryState(), dataDirectory: directory, isTesting: false,
            standardApplicationRoots: [], scanner: scanner)
        model.isReady = true
        do {
            try await operation(model, scanner)
            await finish(model, scanner: scanner)
        } catch {
            await finish(model, scanner: scanner)
            throw error
        }
    }

    private func finish(_ model: LauncherModel, scanner: ControlledScanner) async {
        let scan = model.scanTask
        model.pauseCatalogUpdates()
        await scanner.cancelAll()
        await scan?.value
        model.saveTask?.cancel()
        await model.saveTask?.value
        model.undoManager.removeAllActions()
    }
}

private actor ControlledScanner: ApplicationScanning {
    let started = TestSignal()
    private var pending: [Int: CheckedContinuation<ApplicationScanResult, any Error>] = [:]
    private(set) var callCount = 0

    func scan(roots: [ApplicationScanRoot]) async throws -> ApplicationScanResult {
        let index = callCount
        callCount += 1
        // Deliberately noncooperative: tests can deliver an old result after cancellation.
        return try await withCheckedThrowingContinuation { continuation in
            pending[index] = continuation
            Task { await started.advance() }
        }
    }

    func finish(_ index: Int, records: [ApplicationRecord]) {
        pending.removeValue(forKey: index)?.resume(
            returning: ApplicationScanResult(records: records, roots: []))
    }

    func fail(_ index: Int, cancelled: Bool) {
        pending.removeValue(forKey: index)?.resume(
            throwing: cancelled ? CancellationError() : CocoaError(.fileReadUnknown))
    }

    func cancelAll() {
        let continuations = pending.values
        pending.removeAll()
        for continuation in continuations { continuation.resume(throwing: CancellationError()) }
    }
}
