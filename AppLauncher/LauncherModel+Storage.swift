import AppKit
import LauncherCore
import LauncherInfrastructure

extension LauncherModel {
    var roots: [ApplicationScanRoot] {
        standardApplicationRoots
            + preferences.customApplicationFolders.map {
                ApplicationScanRoot(id: $0.absoluteString, url: $0, kind: .custom)
            }
    }

    func start() async {
        icons.onLoadCompletion = { [weak self] completion in
            self?.performance.iconDidComplete(completion)
        }
        icons.onVisibleScopeChanged = { [weak self] urls in
            self?.performance.beginVisibleIconScope(urls: urls)
        }
        isScanning = true
        var cached: [ApplicationRecord] = []
        do {
            if let catalog = try await store.loadCatalog() {
                cached = catalog.records
                discoveryRootsByPath = catalog.discoveryRootsByPath
            }
        } catch {
            message = "The application cache will be rebuilt."
        }
        do {
            switch try await store.load() {
            case .notFound: library = try LibraryState(records: cached)
            case .loaded(let document): library = try document.libraryState(records: cached)
            case .recoveryAvailable(let backup, _):
                library = try backup.libraryState(records: cached)
                recoveryLocked = true
                hasBackup = true
                message =
                    "Your saved layout needs attention. A backup is available; the original is preserved."
            }
        } catch {
            recoveryLocked = true
            message =
                "Your saved layout could not be read. The original is preserved. Import a valid layout to recover."
            do { library = try LibraryState(records: cached) } catch {
                message = "The application cache is invalid and will be rebuilt."
            }
        }
        collection = preferences.startCollection
        if collection == .favorites && !preferences.showsFavorites { collection = .all }
        if collection == .recents && !preferences.showsRecents { collection = .all }
        isReady = true
        refreshItems()
        updateIconPriorityScope()
        do { if !recoveryLocked { try onPreferencesChanged?() } } catch {
            if error as? GlobalShortcut.RegistrationError == .conflict {
                message =
                    "This shortcut is already in use by another app. Record a different shortcut."
            } else {
                message = "The saved keyboard shortcut is unavailable. Choose another in Settings."
            }
        }
        if isTesting {
            await loadFixtures()
        } else {
            startWatching()
            refreshCatalog()
        }
    }

    func startWatching() {
        guard !isTesting else { return }
        changes.start(roots: roots.map(\.url)) { [weak self] change in
            self?.requestCatalogRefresh(for: change)
        }
    }

    func requestCatalogRefresh(for change: CatalogChangeBatch) {
        guard !isTesting else { return }
        invalidatePresentationReadiness()
        if change.requiresFullInvalidation {
            icons.removeAll()
        } else {
            icons.invalidate(changedPaths: change.changedPaths)
        }
        refreshCatalog()
    }

    func refreshCatalog() {
        guard !isTesting else { return }
        scanRequestTask?.cancel()
        scanRequestTask = nil
        if scanTask != nil {
            scanNeedsRefresh = true
            return
        }
        scanNeedsRefresh = false
        scanGeneration += 1
        let generation = scanGeneration
        let roots = roots
        isScanning = true
        let refreshMeasurement = performance.beginCatalogRefresh()
        var refreshSucceeded = false
        scanTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                performance.endCatalogRefresh(refreshMeasurement, succeeded: refreshSucceeded)
                finishCatalogScan(generation: generation)
            }
            do {
                let result = try await scanner.scan(roots: roots)
                guard !Task.isCancelled, generation == scanGeneration else { return }
                let previousRecords = library.records
                let merged = CatalogScanMerger.reconcile(
                    previous: library.records, scan: result,
                    previousDiscoveryRootsByPath: discoveryRootsByPath)
                _ = try library.reconcileCatalog(merged.reconciliation.records)
                discoveryRootsByPath = merged.discoveryRootsByPath
                icons.removeAll(ifCatalogChangedFrom: previousRecords, to: library.records)
                refreshItems()
                updateIconPriorityScope()
                pruneRecents()
                catalogMessage = nil
                if result.roots.contains(where: { $0.completeness != .complete }) {
                    let folderIssues = result.roots.flatMap(\.issues).contains {
                        $0.kind != .invalidApplicationMetadata
                    }
                    catalogMessage =
                        folderIssues
                        ? "Some application folders are unavailable. Their saved arrangement is preserved."
                        : "Some application details could not be read. Other applications are ready."
                }
                try await store.saveCatalog(
                    ApplicationCatalog(
                        records: library.records, generation: UInt64(generation),
                        discoveryRootsByPath: discoveryRootsByPath))
                scheduleSave()
                refreshSucceeded = true
            } catch is CancellationError {
                return
            } catch {
                catalogMessage =
                    "Applications could not refresh. Your current catalog and arrangement are preserved."
            }
        }
    }

    func restartCatalogForChangedRoots() {
        guard !isTesting else { return }
        scanRequestTask?.cancel()
        scanRequestTask = nil
        scanTask?.cancel()
        scanTask = nil
        scanNeedsRefresh = false
        scanGeneration += 1
        isScanning = false
        startWatching()
        refreshCatalog()
    }

    private func finishCatalogScan(generation: Int) {
        guard generation == scanGeneration else { return }
        scanTask = nil
        isScanning = false
        hasCompletedInitialScan = true
        guard scanNeedsRefresh else { return }
        scanNeedsRefresh = false
        refreshCatalog()
    }

    func scheduleSave() {
        guard isReady, !recoveryLocked else { return }
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(300))
                guard let self else { return }
                try await store.save(document())
            } catch is CancellationError {
                return
            } catch {
                self?.message =
                    "Your latest changes could not be saved. Check available space and folder access."
            }
        }
    }

    func document() throws -> PersistentDocument {
        try PersistentDocument(
            preferences: preferences, organization: library.organization,
            applicationReferences: library.applicationReferences)
    }

    func flush() async -> Bool {
        saveTask?.cancel()
        guard isReady, !recoveryLocked else { return true }
        do {
            try await store.save(document())
            return true
        } catch {
            message = "Your latest changes could not be saved."
            return false
        }
    }

    func restoreBackup() {
        let pendingSave = saveTask
        pendingSave?.cancel()
        saveTask = nil
        pauseCatalogUpdates()
        let previous = library
        let wasLocked = recoveryLocked
        recoveryLocked = true
        Task { @MainActor in
            await pendingSave?.value
            do {
                let backup: PersistentDocument
                switch try await store.load() {
                case .recoveryAvailable(let document, _): backup = document
                case .loaded, .notFound:
                    library = previous
                    recoveryLocked = wasLocked
                    resumeCatalogUpdates()
                    message = "No pending backup recovery is available."
                    return
                }
                let candidate = try backup.libraryState(records: previous.records)
                library = candidate
                do {
                    try onPreferencesChanged?()
                } catch {
                    library = previous
                    recoveryLocked = wasLocked
                    try? onPreferencesChanged?()
                    resumeCatalogUpdates()
                    message =
                        "The backup uses an unavailable keyboard shortcut. Nothing was restored."
                    return
                }
                _ = try await store.restoreBackup()
                recoveryLocked = false
                hasBackup = false
                message = "Your backup was restored."
                clearStaleFolderSelection()
                refreshItems()
                resumeCatalogUpdates()
            } catch {
                library = previous
                recoveryLocked = wasLocked
                try? onPreferencesChanged?()
                resumeCatalogUpdates()
                message =
                    "The backup could not be restored. The current in-memory layout is unchanged."
            }
        }
    }

    func clearStaleFolderSelection() {
        guard let openFolderID, !library.folders.contains(where: { $0.id == openFolderID }) else {
            return
        }
        self.openFolderID = nil
    }

    func resumeCatalogUpdates() {
        startWatching()
        refreshCatalog()
    }

    func pauseCatalogUpdates() {
        scanRequestTask?.cancel()
        scanRequestTask = nil
        scanTask?.cancel()
        scanTask = nil
        scanNeedsRefresh = false
        scanGeneration += 1
        isScanning = false
        changes.stop()
    }

    private func loadFixtures() async {
        var names = [
            "Notes", "Calendar", "Calculator", "Safari", "Mail", "Terminal", "Preview", "Music",
            "Photos", "Unavailable",
        ]
        if ProcessInfo.processInfo.arguments.contains("--benchmark-invocation") {
            names += (1...990).map { String(format: "Sample %04d", $0) }
        } else if ProcessInfo.processInfo.arguments.contains("--dense-ui-fixture") {
            names += (1...40).map { "Sample \($0)" }
        }
        var fixtures = names.map { name in
            ApplicationRecord(
                id: "fixture-\(name.lowercased())", name: name,
                bundleIdentifier: "org.example.fixture.\(name.lowercased())",
                url: URL(fileURLWithPath: "/System/Applications/\(name).app"))
        }
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--trash-fixture-path"),
            arguments.indices.contains(index + 1)
        {
            fixtures.append(
                ApplicationRecord(
                    id: "fixture-disposable", name: "Disposable",
                    bundleIdentifier: "org.example.fixture.disposable",
                    url: URL(fileURLWithPath: arguments[index + 1])
                ))
        }
        do { _ = try library.reconcileCatalog(fixtures) } catch {
            message = "Test fixtures could not be loaded."
        }
        isScanning = false
        hasCompletedInitialScan = true
        refreshItems()
        updateIconPriorityScope()
        scheduleSave()
    }

    func updateIconPriorityScope() {
        let current = iconURLs(for: Array(pageItems))
        let adjacentItems = [page - 1, page + 1].flatMap {
            GridPaginator.items(onPage: $0, from: items, capacity: capacity)
        }
        let adjacent = iconURLs(for: Array(adjacentItems))
        icons.updatePriorityScope(
            currentPage: current.full,
            folderThumbnails: current.thumbnails,
            adjacentPage: adjacent.full + adjacent.thumbnails
        )
    }

    private func iconURLs(for items: [LauncherCore.LibraryItem])
        -> (full: [URL], thumbnails: [URL])
    {
        var full: [URL] = []
        var thumbnails: [URL] = []
        for item in items {
            switch item {
            case .application(let id):
                if let url = record(id)?.url { full.append(url) }
            case .folder(let id):
                thumbnails.append(
                    contentsOf: Array(
                        (folder(id)?.applicationIDs
                            .filter { !library.hiddenIDs.contains($0) }
                            .compactMap { record($0)?.url } ?? []).prefix(9)))
            }
        }
        return (full, thumbnails)
    }
}
