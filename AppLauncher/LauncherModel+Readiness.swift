import AppKit
import LauncherCore

extension LauncherModel {
    private struct PageReadiness {
        let completed: Bool
        let usedFallback: Bool
        let stale: Bool
    }

    func prepareForPresentation(on screen: NSScreen) async -> PresentationReadiness {
        await prepareForPresentation { await wallpaper.prewarm(for: screen) }
    }

    func prepareForPresentation(
        wallpaperPreparation: @MainActor () async -> WallpaperService.State
    ) async -> PresentationReadiness {
        await waitForInitialCatalog()
        guard !Task.isCancelled else { return .cancelled }
        let generation = readinessGeneration
        let wallpaperState = await wallpaperPreparation()
        guard !Task.isCancelled else { return .cancelled }
        guard generation == readinessGeneration else { return .stale }
        let pageReadiness = await preparePage(
            page, iconSize: resolvedIconSize, priority: .visiblePage)
        guard !Task.isCancelled else { return .cancelled }
        guard generation == readinessGeneration else { return .stale }
        if pageReadiness.stale { return .stale }
        guard pageReadiness.completed else { return .cancelled }
        if pageReadiness.usedFallback {
            return .fallback
        }
        if case .unavailable = wallpaperState {
            return .fallback
        }
        return wallpaperState == .ready ? .ready : .stale
    }

    func prewarmForLogin(on screen: NSScreen) async {
        var readiness = await prepareForPresentation(on: screen)
        if readiness == .stale {
            readiness = await prepareForPresentation(on: screen)
        }
        guard readiness == .ready || readiness == .fallback else { return }
        _ = await prewarmAdjacentPage(iconSize: resolvedIconSize)
    }

    func activatePreparedPresentation() {
        wallpaper.activatePrepared()
        login.refresh()
    }

    func requestPage(_ requestedPage: Int) {
        let destination = GridPaginator.clampedPage(
            requestedPage, itemCount: items.count, capacity: capacity)
        guard destination != page else { return }
        guard pendingPageDestination != destination || pageChangeTask == nil else { return }
        pageChangeTask?.cancel()
        pendingPageDestination = destination
        pageChangeTask = Task { @MainActor [weak self] in
            defer {
                if self?.pendingPageDestination == destination {
                    self?.pendingPageDestination = nil
                    self?.pageChangeTask = nil
                }
            }
            _ = await self?.changePageWhenReady(to: destination)
        }
    }

    @discardableResult
    func changePageWhenReady(_ delta: Int) async -> Bool {
        let destination = GridPaginator.clampedPage(
            page + delta, itemCount: items.count, capacity: capacity)
        return await changePageWhenReady(to: destination)
    }

    @discardableResult
    func prewarmAdjacentPage(iconSize: CGFloat) async -> Bool {
        guard pageCount > 1 else { return true }
        let generation = readinessGeneration
        let destinations = [page + 1, page - 1].filter { 0..<pageCount ~= $0 }
        for destination in destinations {
            let readiness = await preparePage(
                destination, iconSize: iconSize, priority: .adjacentPage)
            guard readiness.completed, !readiness.stale, !Task.isCancelled,
                generation == readinessGeneration
            else { return false }
        }
        trimPrewarmedPages(keeping: Set([page] + destinations))
        return true
    }

    private func changePageWhenReady(to destination: Int) async -> Bool {
        guard destination != page else { return false }
        let generation = readinessGeneration
        var readiness = PageReadiness(completed: false, usedFallback: false, stale: true)
        for attempt in 0..<3 where readiness.stale {
            if attempt > 0 { await Task.yield() }
            guard !Task.isCancelled, generation == readinessGeneration else { return false }
            readiness = await preparePage(
                destination, iconSize: resolvedIconSize, priority: .visiblePage)
        }
        guard readiness.completed, !Task.isCancelled, generation == readinessGeneration else {
            return false
        }
        page = destination
        selection = destination * capacity
        trimPrewarmedPages(keeping: [destination])
        return true
    }

    private func preparePage(
        _ page: Int,
        iconSize: CGFloat,
        priority: ApplicationIconRequestPriority
    ) async -> PageReadiness {
        let generation = readinessGeneration
        if let entries = prewarmedPageEntries[page], entries.allSatisfy(\.isLoaded) {
            guard icons.containsCurrentEntries(entries) else {
                prewarmedPageEntries.removeValue(forKey: page)
                return PageReadiness(completed: false, usedFallback: false, stale: true)
            }
            return PageReadiness(
                completed: true,
                usedFallback: entries.contains { !$0.hasRealImage },
                stale: false)
        }
        let pageItems = Array(
            GridPaginator.items(onPage: page, from: items, capacity: capacity))
        var entries: [ApplicationIconEntry] = []
        for item in pageItems {
            switch item {
            case .application(let id):
                if let url = record(id)?.url {
                    entries.append(icons.entry(for: url, size: iconSize, priority: priority))
                }
            case .folder(let id):
                let urls = Array(
                    (folder(id)?.applicationIDs
                        .filter { !library.hiddenIDs.contains($0) }
                        .compactMap { record($0)?.url } ?? []).prefix(9)
                )
                entries.append(
                    contentsOf: urls.map {
                        icons.entry(for: $0, size: iconSize / 4, priority: priority)
                    })
            }
        }
        prewarmedPageEntries[page] = entries
        let waitResult = await icons.waitUntilTerminal(entries)
        guard generation == readinessGeneration else {
            return PageReadiness(completed: false, usedFallback: false, stale: true)
        }
        switch waitResult {
        case .ready:
            break
        case .timedOut:
            guard icons.containsCurrentEntries(entries) else {
                return PageReadiness(completed: false, usedFallback: false, stale: true)
            }
            icons.completeAsTerminalFallback(entries)
        case .cancelled:
            return PageReadiness(completed: false, usedFallback: false, stale: false)
        }
        guard icons.containsCurrentEntries(entries) else {
            prewarmedPageEntries.removeValue(forKey: page)
            return PageReadiness(completed: false, usedFallback: false, stale: true)
        }
        return PageReadiness(
            completed: entries.allSatisfy(\.isLoaded),
            usedFallback: entries.contains { !$0.hasRealImage },
            stale: false
        )
    }

    private func trimPrewarmedPages(keeping pages: Set<Int>) {
        prewarmedPageEntries = prewarmedPageEntries.filter { pages.contains($0.key) }
    }

    private func waitForInitialCatalog() async {
        while !hasCompletedInitialScan, let initialScan = scanTask {
            await initialScan.value
            if Task.isCancelled { return }
        }
    }
}
