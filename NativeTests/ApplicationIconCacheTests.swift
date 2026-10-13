import AppKit
import CoreServices
import Foundation
import LauncherCore
import Testing

@testable import AppLauncher

@Suite
@MainActor
struct ApplicationIconCacheTests {
    @Test
    func failedLoadBecomesTerminalUntilExplicitInvalidation() async throws {
        let loader = NilIconLoader()
        let cache = ApplicationIconCache(countLimit: 4, workerCount: 1, loader: loader)
        defer { cache.removeAll() }
        let url = URL(fileURLWithPath: "/Applications/Missing.app")

        let entry = cache.entry(for: url, size: 64)
        #expect(await waitUntil { entry.isLoaded })
        #expect(cache.entry(for: url, size: 64) === entry)
        for _ in 0..<10 { _ = cache.entry(for: url, size: 64) }
        await Task.yield()

        #expect(await loader.callCount == 1)
        cache.invalidate(changedPaths: [url])
        let replacement = cache.entry(for: url, size: 64)
        #expect(replacement !== entry)
        #expect(await waitUntil { replacement.isLoaded })
        #expect(await loader.callCount == 2)
    }

    @Test
    func unchangedCatalogRetainsEntryAndChangedCatalogInvalidatesOnlyThatURL() async throws {
        let loader = NilIconLoader()
        let cache = ApplicationIconCache(countLimit: 4, workerCount: 1, loader: loader)
        defer { cache.removeAll() }
        let firstURL = URL(fileURLWithPath: "/Applications/Example.app")
        let secondURL = URL(fileURLWithPath: "/Applications/Other.app")
        let record = ApplicationRecord(
            id: "example", name: "Example", bundleIdentifier: "com.example.app", url: firstURL)
        let other = ApplicationRecord(
            id: "other", name: "Other", bundleIdentifier: "com.other.app", url: secondURL)
        let first = cache.entry(for: firstURL, size: 64)
        let second = cache.entry(for: secondURL, size: 64)
        #expect(await waitUntil { first.isLoaded && second.isLoaded })

        cache.removeAll(ifCatalogChangedFrom: [record, other], to: [record, other])
        #expect(cache.entry(for: firstURL, size: 64) === first)
        #expect(cache.entry(for: secondURL, size: 64) === second)

        let updated = ApplicationRecord(
            id: record.id, name: "Example Updated", bundleIdentifier: record.bundleIdentifier,
            url: record.url)
        cache.removeAll(ifCatalogChangedFrom: [record, other], to: [updated, other])
        #expect(cache.entry(for: firstURL, size: 64) !== first)
        #expect(cache.entry(for: secondURL, size: 64) === second)
    }

    @Test
    func samePathBundleEventInvalidatesTheMatchingIcon() async throws {
        let loader = NilIconLoader()
        let cache = ApplicationIconCache(countLimit: 4, workerCount: 1, loader: loader)
        defer { cache.removeAll() }
        let url = URL(fileURLWithPath: "/Applications/Example.app")
        let entry = cache.entry(for: url, size: 64)
        #expect(await waitUntil { entry.isLoaded })

        let iconResource = url.appendingPathComponent("Contents/Resources/AppIcon.icns")
        cache.invalidate(changedPaths: [iconResource])

        #expect(cache.entry(for: url, size: 64) !== entry)
    }

    @Test
    func aNewApplicationEventDoesNotEvictUnchangedIcons() async throws {
        let loader = NilIconLoader()
        let cache = ApplicationIconCache(countLimit: 4, workerCount: 1, loader: loader)
        defer { cache.removeAll() }
        let existingURL = URL(fileURLWithPath: "/Applications/Existing.app")
        let otherURL = URL(fileURLWithPath: "/Applications/Other.app")
        let newURL = URL(fileURLWithPath: "/Applications/New.app")
        let existing = cache.entry(for: existingURL, size: 64)
        let other = cache.entry(for: otherURL, size: 64)
        #expect(await waitUntil { existing.isLoaded && other.isLoaded })

        cache.invalidate(changedPaths: [newURL])

        #expect(cache.entry(for: existingURL, size: 64) === existing)
        #expect(cache.entry(for: otherURL, size: 64) === other)
    }

    @Test
    func visiblePagePriorityPrecedesFolderThumbnailsAndAdjacentPage() async throws {
        let loader = ControlledIconLoader()
        let cache = ApplicationIconCache(workerCount: 1, loader: loader)
        defer { cache.removeAll() }
        let blocker = URL(fileURLWithPath: "/Applications/Blocker.app")
        let visible = URL(fileURLWithPath: "/Applications/Visible.app")
        let thumbnail = URL(fileURLWithPath: "/Applications/Thumbnail.app")
        let adjacent = URL(fileURLWithPath: "/Applications/Adjacent.app")

        _ = cache.entry(for: blocker, size: 64, priority: .adjacentPage)
        try #require(await waitForStarted(loader, count: 1))
        cache.updatePriorityScope(
            currentPage: [visible], folderThumbnails: [thumbnail], adjacentPage: [adjacent])
        let adjacentEntry = cache.entry(for: adjacent, size: 64)
        let thumbnailEntry = cache.entry(for: thumbnail, size: 16)
        let visibleEntry = cache.entry(for: visible, size: 64)

        await loader.releaseNext()
        try #require(await waitForStarted(loader, count: 2))
        #expect(await loader.startedURLs[1] == visible)
        await loader.releaseNext()
        try #require(await waitForStarted(loader, count: 3))
        #expect(await loader.startedURLs[2] == thumbnail)
        await loader.releaseNext()
        try #require(await waitForStarted(loader, count: 4))
        #expect(await loader.startedURLs[3] == adjacent)
        await loader.releaseAll()
        #expect(
            await waitUntil {
                adjacentEntry.isLoaded && thumbnailEntry.isLoaded && visibleEntry.isLoaded
            })
    }

    @Test
    func changingScopeDiscardsPendingOldPageRequests() async throws {
        let loader = ControlledIconLoader()
        let cache = ApplicationIconCache(workerCount: 1, loader: loader)
        defer { cache.removeAll() }
        let blocker = URL(fileURLWithPath: "/Applications/Blocker.app")
        let oldPage = URL(fileURLWithPath: "/Applications/OldPage.app")
        let newPage = URL(fileURLWithPath: "/Applications/NewPage.app")

        cache.updatePriorityScope(
            currentPage: [blocker, oldPage], folderThumbnails: [], adjacentPage: [])
        _ = cache.entry(for: blocker, size: 64)
        try #require(await waitForStarted(loader, count: 1))
        let obsolete = cache.entry(for: oldPage, size: 24)
        let oldWaiter = Task { await obsolete.waitUntilLoaded(timeout: .seconds(5)) }

        cache.updatePriorityScope(
            currentPage: [newPage], folderThumbnails: [], adjacentPage: [])
        _ = cache.entry(for: newPage, size: 64)

        try #require(await waitForStarted(loader, count: 2))
        #expect(await loader.startedURLs[1] == newPage)
        #expect(await oldWaiter.value == false)
        await loader.releaseAll()
        try #require(await loader.completed.wait(for: 2))
        #expect(await loader.startedURLs == [blocker, newPage])
        cache.updatePriorityScope(currentPage: [oldPage], folderThumbnails: [], adjacentPage: [])
        let reloaded = cache.entry(for: oldPage, size: 24)
        #expect(reloaded !== obsolete)
        try #require(await waitForStarted(loader, count: 3))
        await loader.releaseAll()
        #expect(await reloaded.waitUntilLoaded(timeout: .seconds(5)))
    }

    @Test
    func schedulerNeverStartsMoreThanThreeDecodes() async throws {
        let loader = ControlledIconLoader()
        let cache = ApplicationIconCache(workerCount: 3, loader: loader)
        defer { cache.removeAll() }
        let entries = (0..<8).map { index in
            cache.entry(
                for: URL(fileURLWithPath: "/Applications/App\(index).app"),
                size: 64,
                priority: .visiblePage)
        }

        try #require(await waitForStarted(loader, count: 3))
        #expect(await loader.maximumActive == 3)
        #expect(await loader.activeCount == 3)
        await loader.releaseAll()
        try #require(await waitForStarted(loader, count: 6))
        #expect(await loader.activeCount == 3)
        await loader.releaseAll()
        try #require(await waitForStarted(loader, count: 8))
        await loader.releaseAll()
        #expect(await waitUntil { entries.allSatisfy(\.isLoaded) })
    }

    @Test
    func pendingQueueEvictsTheLowestPriorityRequest() async throws {
        let loader = ControlledIconLoader()
        let cache = ApplicationIconCache(
            workerCount: 1, pendingLimit: 2, loader: loader)
        let blocker = URL(fileURLWithPath: "/Applications/Blocker.app")
        let lowOne = URL(fileURLWithPath: "/Applications/LowOne.app")
        let lowTwo = URL(fileURLWithPath: "/Applications/LowTwo.app")
        let visible = URL(fileURLWithPath: "/Applications/Visible.app")

        _ = cache.entry(for: blocker, size: 64, priority: .adjacentPage)
        try #require(await waitForStarted(loader, count: 1))
        let lowOneEntry = cache.entry(for: lowOne, size: 64, priority: .adjacentPage)
        let lowTwoEntry = cache.entry(for: lowTwo, size: 64, priority: .adjacentPage)
        _ = cache.entry(for: visible, size: 64, priority: .visiblePage)

        await loader.releaseAll()
        try #require(await waitForStarted(loader, count: 2))
        #expect(await loader.startedURLs[1] == visible)
        await loader.releaseAll()
        try #require(await waitForStarted(loader, count: 3))
        #expect(await loader.startedURLs[2] == lowOne)
        await loader.releaseAll()
        #expect(await waitUntil { lowOneEntry.isLoaded })
        #expect(!lowTwoEntry.isLoaded)
    }

    @Test
    func invalidatingAnActiveRequestCancelsItAndDiscardsItsResult() async throws {
        let loader = ControlledIconLoader()
        let cache = ApplicationIconCache(workerCount: 1, loader: loader)
        defer { cache.removeAll() }
        let url = URL(fileURLWithPath: "/Applications/Example.app")
        let oldEntry = cache.entry(for: url, size: 64)
        try #require(await waitForStarted(loader, count: 1))

        cache.invalidate(changedPaths: [url])
        let newEntry = cache.entry(for: url, size: 64)
        await loader.releaseAll()
        try #require(await waitForStarted(loader, count: 2))
        await loader.releaseAll()

        #expect(await waitUntil { newEntry.isLoaded })
        #expect(!oldEntry.isLoaded)
        #expect(await loader.callCount == 2)
    }

    @Test
    func invalidatingALoadedEntryRemovesItFromTheReadinessIdentitySet() async throws {
        let cache = ApplicationIconCache(workerCount: 1, loader: NilIconLoader())
        let url = URL(fileURLWithPath: "/Applications/Loaded.app")
        let entry = cache.entry(for: url, size: 64)
        #expect(await waitUntil { entry.isLoaded })
        #expect(cache.containsCurrentEntries([entry]))

        cache.invalidate(changedPaths: [url])

        #expect(!cache.containsCurrentEntries([entry]))
    }

    @Test
    func visibleEntrySurvivesCacheEvictionWhileItIsCurrent() async throws {
        let loader = NilIconLoader()
        let cache = ApplicationIconCache(
            countLimit: 1, totalCostLimit: 1, workerCount: 1, loader: loader)
        let firstURL = URL(fileURLWithPath: "/Applications/First.app")
        let secondURL = URL(fileURLWithPath: "/Applications/Second.app")
        cache.updatePriorityScope(
            currentPage: [firstURL], folderThumbnails: [], adjacentPage: [])
        let first = cache.entry(for: firstURL, size: 64)
        #expect(await waitUntil { first.isLoaded })
        cache.updatePriorityScope(
            currentPage: [firstURL], folderThumbnails: [], adjacentPage: [])
        let second = cache.entry(for: secondURL, size: 64)
        #expect(await waitUntil { second.isLoaded })

        #expect(cache.entry(for: firstURL, size: 64) === first)
    }

    @Test
    func adjacentPageEntryIsRetainedUntilThePriorityScopeChanges() async throws {
        let loader = NilIconLoader()
        let cache = ApplicationIconCache(
            countLimit: 1, totalCostLimit: 1, workerCount: 1, loader: loader)
        let currentURL = URL(fileURLWithPath: "/Applications/Current.app")
        let adjacentURL = URL(fileURLWithPath: "/Applications/Adjacent.app")
        cache.updatePriorityScope(
            currentPage: [currentURL], folderThumbnails: [], adjacentPage: [adjacentURL])
        let current = cache.entry(for: currentURL, size: 64)
        let adjacent = cache.entry(for: adjacentURL, size: 64)
        #expect(await waitUntil { current.isLoaded && adjacent.isLoaded })

        _ = cache.entry(for: URL(fileURLWithPath: "/Applications/Other.app"), size: 64)

        #expect(cache.entry(for: adjacentURL, size: 64) === adjacent)
    }

    @Test
    func previousAndNextPageEntriesAreRetainedTogether() async throws {
        let loader = NilIconLoader()
        let cache = ApplicationIconCache(
            countLimit: 1, totalCostLimit: 1, workerCount: 3, loader: loader)
        let previousURL = URL(fileURLWithPath: "/Applications/Previous.app")
        let currentURL = URL(fileURLWithPath: "/Applications/Current.app")
        let nextURL = URL(fileURLWithPath: "/Applications/Next.app")
        cache.updatePriorityScope(
            currentPage: [currentURL], folderThumbnails: [],
            adjacentPage: [previousURL, nextURL])
        let previous = cache.entry(for: previousURL, size: 64)
        let current = cache.entry(for: currentURL, size: 64)
        let next = cache.entry(for: nextURL, size: 64)
        #expect(await waitUntil { previous.isLoaded && current.isLoaded && next.isLoaded })

        _ = cache.entry(for: URL(fileURLWithPath: "/Applications/Other.app"), size: 64)

        #expect(cache.entry(for: previousURL, size: 64) === previous)
        #expect(cache.entry(for: nextURL, size: 64) === next)
    }

    @Test
    func readinessTimeoutCreatesAStableTerminalFallback() async throws {
        let loader = ControlledIconLoader()
        let cache = ApplicationIconCache(workerCount: 1, loader: loader)
        defer { cache.removeAll() }
        let url = URL(fileURLWithPath: "/Applications/Slow.app")
        let entry = cache.entry(for: url, size: 64)
        try #require(await waitForStarted(loader, count: 1))

        cache.completeAsTerminalFallback([entry])
        await loader.releaseAll()
        try #require(await loader.completed.wait())

        #expect(entry.isLoaded)
        #expect(!entry.hasRealImage)
        #expect(cache.entry(for: url, size: 64) === entry)
    }

    @Test
    func successfulReadinessUsesARealDecodedIcon() async throws {
        let cache = ApplicationIconCache(workerCount: 1, loader: SuccessfulIconLoader())
        let entry = cache.entry(
            for: URL(fileURLWithPath: "/Applications/Ready.app"), size: 64)

        #expect(await cache.waitUntilTerminal([entry]) == .ready)
        #expect(entry.isLoaded)
        #expect(entry.hasRealImage)
    }

    @Test
    func pageChangeWaitsForDestinationIconsBeforeUpdatingTheVisiblePage() async throws {
        let loader = ControlledIconLoader()
        let cache = ApplicationIconCache(workerCount: 1, loader: loader)
        defer { cache.removeAll() }
        let records = [
            ApplicationRecord(
                id: "first", name: "First", bundleIdentifier: "example.first",
                url: URL(fileURLWithPath: "/Applications/First.app")),
            ApplicationRecord(
                id: "second", name: "Second", bundleIdentifier: "example.second",
                url: URL(fileURLWithPath: "/Applications/Second.app")),
        ]
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppLauncherPageReadiness-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = LauncherModel(
            library: try LibraryState(records: records), dataDirectory: directory,
            isTesting: true, icons: cache)
        model.isReady = true
        model.columns = 1
        model.rows = 1
        model.resolvedIconSize = 64
        model.refreshItems()

        model.requestPage(1)
        try #require(await waitForStarted(loader, count: 1))
        #expect(model.page == 0)
        await loader.releaseAll()
        #expect(await waitUntil { model.page == 1 })
    }

    @Test
    func keyboardPageNavigationWaitsForDestinationIcons() async throws {
        let loader = ControlledIconLoader()
        let cache = ApplicationIconCache(workerCount: 1, loader: loader)
        defer { cache.removeAll() }
        let records = [
            ApplicationRecord(
                id: "first", name: "First", bundleIdentifier: "example.first",
                url: URL(fileURLWithPath: "/Applications/First.app")),
            ApplicationRecord(
                id: "second", name: "Second", bundleIdentifier: "example.second",
                url: URL(fileURLWithPath: "/Applications/Second.app")),
        ]
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppLauncherKeyboardReadiness-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = LauncherModel(
            library: try LibraryState(records: records), dataDirectory: directory,
            isTesting: true, icons: cache)
        model.isReady = true
        model.columns = 1
        model.rows = 1
        model.resolvedIconSize = 64
        model.refreshItems()

        model.navigate(.nextPage)
        try #require(await waitForStarted(loader, count: 1))
        #expect(model.page == 0)
        await loader.releaseAll()
        #expect(await waitUntil { model.page == 1 })
    }

    @Test
    func navigatingToAnAlreadyPrewarmedPageStartsNoNewIconLoad() async throws {
        let loader = ControlledIconLoader()
        let cache = ApplicationIconCache(workerCount: 1, loader: loader)
        defer { cache.removeAll() }
        let records = [
            ApplicationRecord(
                id: "first", name: "First", bundleIdentifier: "example.first",
                url: URL(fileURLWithPath: "/Applications/First.app")),
            ApplicationRecord(
                id: "second", name: "Second", bundleIdentifier: "example.second",
                url: URL(fileURLWithPath: "/Applications/Second.app")),
        ]
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppLauncherWarmPage-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = LauncherModel(
            library: try LibraryState(records: records), dataDirectory: directory,
            isTesting: true, icons: cache)
        model.isReady = true
        model.columns = 1
        model.rows = 1
        model.resolvedIconSize = 64
        model.refreshItems()

        let prewarm = Task { await model.prewarmAdjacentPage(iconSize: 64) }
        try #require(await waitForStarted(loader, count: 1))
        await loader.releaseAll()
        #expect(await prewarm.value)
        let loadCount = await loader.callCount

        model.requestPage(1)

        #expect(await waitUntil { model.page == 1 })
        #expect(await loader.callCount == loadCount)
    }

    @Test
    func pageChangeReloadsAnInvalidatedPrewarmedIconBeforeUpdatingTheVisiblePage() async throws {
        let loader = ControlledIconLoader()
        let cache = ApplicationIconCache(workerCount: 1, loader: loader)
        defer { cache.removeAll() }
        let secondURL = URL(fileURLWithPath: "/Applications/Second.app")
        let records = [
            ApplicationRecord(
                id: "first", name: "First", bundleIdentifier: "example.first",
                url: URL(fileURLWithPath: "/Applications/First.app")),
            ApplicationRecord(
                id: "second", name: "Second", bundleIdentifier: "example.second",
                url: secondURL),
        ]
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppLauncherPageInvalidation-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = LauncherModel(
            library: try LibraryState(records: records), dataDirectory: directory,
            isTesting: true, icons: cache)
        model.isReady = true
        model.columns = 1
        model.rows = 1
        model.resolvedIconSize = 64
        model.refreshItems()

        model.requestPage(1)
        try #require(await waitForStarted(loader, count: 1))
        await loader.releaseAll()
        #expect(await waitUntil { model.page == 1 })

        model.page = 0
        cache.invalidate(changedPaths: [secondURL])
        model.requestPage(1)

        try #require(await waitForStarted(loader, count: 2))
        #expect(model.page == 0)
        await loader.releaseAll()
        #expect(await waitUntil { model.page == 1 })
    }

    @Test
    func preparingToShowPreservesCompatibleBackgroundPrewarmEntries() async throws {
        let cache = ApplicationIconCache(workerCount: 1, loader: NilIconLoader())
        let records = [
            ApplicationRecord(
                id: "first", name: "First", bundleIdentifier: "example.first",
                url: URL(fileURLWithPath: "/Applications/First.app")),
            ApplicationRecord(
                id: "second", name: "Second", bundleIdentifier: "example.second",
                url: URL(fileURLWithPath: "/Applications/Second.app")),
        ]
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppLauncherPrewarmRetention-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = LauncherModel(
            library: try LibraryState(records: records), dataDirectory: directory,
            isTesting: true, icons: cache)
        model.isReady = true
        model.columns = 1
        model.rows = 1
        model.resolvedIconSize = 64
        model.refreshItems()

        await model.prewarmAdjacentPage(iconSize: 64)
        let prewarmed = model.prewarmedPageEntries[1]
        #expect(prewarmed?.allSatisfy(\.isLoaded) == true)

        model.prepareToShow()

        #expect(model.prewarmedPageEntries[1]?.first === prewarmed?.first)
    }

    @Test
    func presentationWaitsForVisibleIconsButNotAdjacentIcons() async throws {
        let loader = ControlledIconLoader()
        let cache = ApplicationIconCache(workerCount: 1, loader: loader)
        defer { cache.removeAll() }
        let records = (0..<2).map {
            ApplicationRecord(
                id: "app-\($0)", name: "App \($0)", bundleIdentifier: nil,
                url: URL(fileURLWithPath: "/synthetic/App\($0).app"))
        }
        let model = LauncherModel(
            library: try LibraryState(records: records),
            dataDirectory: FileManager.default.temporaryDirectory.appending(
                path: UUID().uuidString),
            isTesting: true, icons: cache)
        model.columns = 1
        model.rows = 1
        model.refreshItems()
        var completed = false
        let presentation = Task {
            let result = await model.prepareForPresentation { .ready }
            completed = true
            return result
        }
        try #require(await loader.started.wait())
        #expect(!completed)
        await loader.releaseAll()
        #expect(await presentation.value == .fallback)
        #expect(await loader.callCount == 1)

        let adjacent = Task { await model.prewarmAdjacentPage(iconSize: 76) }
        try #require(await loader.started.wait(for: 2))
        #expect(await model.prepareForPresentation { .ready } == .fallback)
        #expect(await loader.activeCount == 1)
        await loader.releaseAll()
        #expect(await adjacent.value)
    }

    @Test
    func searchUpdateMeasurementsIgnoreStaleAndDuplicateViewAcknowledgements() {
        let probe = LaunchPerformanceProbe(enabled: true)
        probe.beginSearchUpdate(query: "old")
        probe.beginSearchUpdate(query: "current")
        probe.didUpdateSearch(query: "old")
        #expect(probe.searchUpdateSamples.isEmpty)
        probe.didUpdateSearch(query: "current")
        probe.didUpdateSearch(query: "current")
        #expect(probe.searchUpdateSamples.count == 1)
        let disabled = LaunchPerformanceProbe(enabled: false)
        disabled.beginSearchUpdate(query: "query")
        disabled.didUpdateSearch(query: "query")
        #expect(disabled.searchUpdateSamples.isEmpty)
    }

    @Test
    func performanceProbeRecordsFocusAndIconReadinessSeparately() {
        let probe = LaunchPerformanceProbe(enabled: true)
        let firstURL = URL(fileURLWithPath: "/Applications/First.app")
        let secondURL = URL(fileURLWithPath: "/Applications/Second.app")
        probe.beginInvocation()
        probe.beginVisibleIconScope(urls: [firstURL, secondURL])
        probe.iconDidComplete(
            ApplicationIconLoadCompletion(
                key: "first|128", url: firstURL, priority: .visiblePage, loaded: false))
        #expect(probe.lastFirstRealVisibleIconMilliseconds == nil)
        probe.iconDidComplete(
            ApplicationIconLoadCompletion(
                key: "second|128", url: secondURL, priority: .visiblePage, loaded: true))
        #expect(probe.lastFirstRealVisibleIconMilliseconds != nil)
        #expect(probe.lastAllVisibleIconsMilliseconds != nil)
        probe.didFocusSearch(windowIsKey: true)
        #expect(probe.lastMilliseconds != nil)
        #expect(probe.iconSummary()?.allVisibleIconsCount == 1)
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            if condition() { return true }
            do { try await Task.sleep(for: .milliseconds(1)) } catch { return false }
        }
        return condition()
    }

    private func waitForStarted(_ loader: ControlledIconLoader, count: Int) async -> Bool {
        await loader.started.wait(for: count)
    }
}

@Suite
struct CatalogChangeObserverTests {
    @Test
    func droppedAndUnresolvableEventsRequireFullInvalidation() {
        let url = URL(fileURLWithPath: "/Applications")
        let dropped = CatalogChangeEvent(
            path: url, flags: UInt32(kFSEventStreamEventFlagUserDropped))
        let rootChanged = CatalogChangeEvent(
            path: url, flags: UInt32(kFSEventStreamEventFlagRootChanged))
        let mustScan = CatalogChangeEvent(
            path: url, flags: UInt32(kFSEventStreamEventFlagMustScanSubDirs))
        let aggregateMustScan = CatalogChangeEvent(
            path: url,
            flags: UInt32(kFSEventStreamEventFlagMustScanSubDirs)
                | UInt32(kFSEventStreamEventFlagItemModified))
        let unknown = CatalogChangeEvent(path: url, flags: 1 << 31)

        #expect(dropped.requiresFullInvalidation)
        #expect(rootChanged.requiresFullInvalidation)
        #expect(mustScan.requiresFullInvalidation)
        #expect(aggregateMustScan.requiresFullInvalidation)
        #expect(unknown.requiresFullInvalidation)
    }

    @Test
    func itemSpecificEventsRetainTheirPathsForTargetedInvalidation() {
        let url = URL(fileURLWithPath: "/Applications/Example.app/Contents/Info.plist")
        let event = CatalogChangeEvent(
            path: url,
            flags: UInt32(kFSEventStreamEventFlagItemModified)
                | UInt32(kFSEventStreamEventFlagItemIsFile)
        )
        let batch = CatalogChangeBatch(events: [event])

        #expect(!event.requiresFullInvalidation)
        #expect(batch.changedPaths == [url])
        #expect(!batch.requiresFullInvalidation)
    }
}

private actor NilIconLoader: ApplicationIconLoading {
    private(set) var callCount = 0

    func load(url: URL, pixelLength: Int) -> CGImage? {
        callCount += 1
        return nil
    }
}

private struct SuccessfulIconLoader: ApplicationIconLoading {
    @concurrent
    func load(url: URL, pixelLength: Int) async -> CGImage? {
        guard
            let context = CGContext(
                data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        return context.makeImage()
    }
}

actor ControlledIconLoader: ApplicationIconLoading {
    let started = TestSignal()
    let completed = TestSignal()
    private var nextID = 0
    private var continuations: [Int: CheckedContinuation<CGImage?, Never>] = [:]
    private(set) var startedURLs: [URL] = []
    private(set) var callCount = 0
    private(set) var activeCount = 0
    private(set) var maximumActive = 0

    func load(url: URL, pixelLength: Int) async -> CGImage? {
        let id = nextID
        nextID += 1
        startedURLs.append(url)
        callCount += 1
        activeCount += 1
        maximumActive = max(maximumActive, activeCount)
        let result = await withTaskCancellationHandler(
            operation: {
                await waitForRelease(id: id)
            },
            onCancel: {
                Task { await self.resume(id: id, result: nil) }
            })
        activeCount -= 1
        await completed.advance()
        return result
    }

    func releaseNext() {
        guard let id = continuations.keys.sorted().first,
            let continuation = continuations.removeValue(forKey: id)
        else { return }
        continuation.resume(returning: nil)
    }

    func releaseAll() {
        let pending = continuations.values
        continuations.removeAll()
        for continuation in pending { continuation.resume(returning: nil) }
    }

    private func waitForRelease(id: Int) async -> CGImage? {
        if Task.isCancelled { return nil }
        return await withCheckedContinuation { continuation in
            if Task.isCancelled {
                continuation.resume(returning: nil)
            } else {
                continuations[id] = continuation
                Task { await started.advance() }
            }
        }
    }

    private func resume(id: Int, result: CGImage?) {
        guard let continuation = continuations.removeValue(forKey: id) else { return }
        continuation.resume(returning: result)
    }
}
