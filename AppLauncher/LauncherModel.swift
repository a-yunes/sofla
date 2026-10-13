import AppKit
import LauncherCore
import LauncherInfrastructure
import Observation

@MainActor @Observable
final class LauncherModel {
    enum DropTarget: Equatable {
        case insertion(beforeItemID: String?)
        case folder(String)
        case applicationMerge(String)
        case favorites
    }

    enum PresentationReadiness: Equatable {
        case ready
        case fallback
        case stale
        case cancelled
    }

    var library: LibraryState
    var query = "" {
        didSet {
            page = 0
            selection = 0
            refreshItems()
        }
    }
    var collection = LauncherPreferences.StartCollection.all {
        didSet {
            page = 0
            selection = 0
            openFolderID = nil
            refreshItems()
        }
    }
    var openFolderID: String? {
        didSet {
            page = 0
            selection = 0
            refreshItems()
        }
    }
    var items: [LauncherCore.LibraryItem] = []
    var page = 0 {
        didSet {
            if page != oldValue { updateIconPriorityScope() }
        }
    }
    var selection = 0
    var columns = 7
    var rows = 5
    var focusGeneration = 0
    var showsKeyboardSelection = false
    var isScanning = true
    var isLaunching = false
    var message: String?
    var catalogMessage: String?
    var recoveryLocked = false
    var hasBackup = false
    var draggedItem: LauncherCore.LibraryItem?
    var dropTarget: DropTarget?
    var dropConfirmation: String?
    var trashEligibleIDs = Set<String>()
    var isPresentationReady = false
    var lastFailedLaunch: ApplicationRecord?
    var launchFailure: String?
    let updates: UpdateService
    let login: LoginService
    let icons: ApplicationIconCache
    let wallpaper = WallpaperService()
    let isTesting: Bool
    let undoManager = UndoManager()
    let performance = LaunchPerformanceProbe(
        enabled: ProcessInfo.processInfo.arguments.contains("--measure-invocation"))
    @ObservationIgnored var onDismiss: ((Bool) -> Void)?
    @ObservationIgnored var onPreferences: (() -> Void)?
    @ObservationIgnored var onPreferencesChanged: (() throws -> Void)?
    @ObservationIgnored let scanner: any ApplicationScanning
    @ObservationIgnored var discoveryRootsByPath: [String: Set<String>] = [:]
    @ObservationIgnored var hasCompletedInitialScan = false
    @ObservationIgnored let standardApplicationRoots: [ApplicationScanRoot]
    @ObservationIgnored let store: PersistentDocumentStore
    @ObservationIgnored let now: @Sendable () -> Date
    @ObservationIgnored let launcher: any ApplicationLaunching
    @ObservationIgnored let recycler: any ApplicationRecycling
    @ObservationIgnored let changes = CatalogChangeObserver()
    @ObservationIgnored var scanTask: Task<Void, Never>?
    @ObservationIgnored var saveTask: Task<Void, Never>?
    @ObservationIgnored var scanGeneration = 0
    @ObservationIgnored var scanNeedsRefresh = false
    @ObservationIgnored var scanRequestTask: Task<Void, Never>?
    @ObservationIgnored var dragPageTask: Task<Void, Never>?
    @ObservationIgnored var pageChangeTask: Task<Void, Never>?
    @ObservationIgnored var pendingPageDestination: Int?
    @ObservationIgnored var dropConfirmationTask: Task<Void, Never>?
    @ObservationIgnored var recycleTask: Task<Void, Never>?
    @ObservationIgnored var trashEligibilityTask: Task<Void, Never>?
    @ObservationIgnored var prewarmedPageEntries: [Int: [ApplicationIconEntry]] = [:]
    @ObservationIgnored var resolvedIconSize: CGFloat = 76
    @ObservationIgnored var readinessGeneration = 0
    var isReady = false
    @ObservationIgnored var recordsByID: [String: ApplicationRecord] = [:]
    @ObservationIgnored var searchIndex = SearchIndex(records: [])
    @ObservationIgnored var indexedRecords: [ApplicationRecord] = []
    @ObservationIgnored var indexedAliases: [String: [String]] = [:]
    @ObservationIgnored var indexedHidden: Set<String> = []
    @ObservationIgnored var onCatalogRefresh: (() -> Void)?

    init(
        library: LibraryState, dataDirectory: URL, isTesting: Bool,
        standardApplicationRoots: [ApplicationScanRoot] = ApplicationScanRoot.standardRoots(),
        scanner: any ApplicationScanning = ApplicationScanner(),
        now: @escaping @Sendable () -> Date = Date.init,
        recycler: any ApplicationRecycling = WorkspaceApplicationRecycler(),
        icons: ApplicationIconCache = ApplicationIconCache()
    ) {
        updates = UpdateService(
            isTesting: isTesting
                || ProcessInfo.processInfo.arguments.contains("--live-verification"))
        login = isTesting ? .fixture() : LoginService()
        self.library = library
        self.isTesting = isTesting
        self.standardApplicationRoots = standardApplicationRoots
        self.scanner = scanner
        self.now = now
        store = PersistentDocumentStore(
            documentURL: dataDirectory.appendingPathComponent("library.json"),
            backupURL: dataDirectory.appendingPathComponent("library.backup.json"),
            catalogURL: dataDirectory.appendingPathComponent("catalog-cache.json")
        )
        launcher = isTesting ? FixtureApplicationLauncher() : WorkspaceApplicationLauncher()
        self.recycler = recycler
        self.icons = icons
        undoManager.levelsOfUndo = 50
        refreshItems()
    }

    var canDrag: Bool { isReady && !recoveryLocked && query.isEmpty && collection != .recents }

    var preferences: LauncherPreferences { library.preferences }
    var capacity: Int { columns * rows }
    var pageCount: Int {
        max(1, GridPaginator.pageCount(itemCount: items.count, capacity: capacity))
    }
    var pageItems: [LauncherCore.LibraryItem] {
        Array(GridPaginator.items(onPage: page, from: items, capacity: capacity))
    }
    var openFolder: ApplicationFolder? { library.folders.first { $0.id == openFolderID } }

    func record(_ id: String) -> ApplicationRecord? { recordsByID[id] }
    func folder(_ id: String) -> ApplicationFolder? { library.folders.first { $0.id == id } }

    func refreshItems() {
        invalidatePresentationReadiness()
        if indexedRecords != library.records || indexedAliases != library.aliases
            || indexedHidden != library.hiddenIDs
        {
            indexedRecords = library.records
            indexedAliases = library.aliases
            indexedHidden = library.hiddenIDs
            searchIndex = SearchIndex(
                records: library.records, aliases: library.aliases, hiddenIDs: library.hiddenIDs)
            recordsByID = Dictionary(uniqueKeysWithValues: library.records.map { ($0.id, $0) })
            trashEligibleIDs.formIntersection(recordsByID.keys)
        }
        let visible = Set(library.visibleRecords.map(\.id))
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items = searchIndex.search(query, typoTolerance: preferences.typoTolerance).map {
                .application($0.id)
            }
        } else if let openFolder {
            items = openFolder.applicationIDs.filter { visible.contains($0) }.map(
                LauncherCore.LibraryItem.application)
        } else {
            switch collection {
            case .all:
                items = library.rootOrder.filter {
                    switch $0 {
                    case .application(let id): visible.contains(id)
                    case .folder(let id):
                        folder(id)?.applicationIDs.contains(where: visible.contains) == true
                    }
                }
            case .favorites:
                items = library.favoriteIDs.filter { visible.contains($0) }.map(
                    LauncherCore.LibraryItem.application)
            case .recents:
                items = library.recents.filter { visible.contains($0.applicationID) }
                    .map { .application($0.applicationID) }
            }
        }
        page = GridPaginator.clampedPage(page, itemCount: items.count, capacity: capacity)
        selection =
            GridNavigation.selectionAfterRemoval(previousIndex: selection, itemCount: items.count)
            ?? 0
        updateIconPriorityScope()
    }

    func invalidatePresentationReadiness() {
        readinessGeneration &+= 1
        pageChangeTask?.cancel()
        pageChangeTask = nil
        pendingPageDestination = nil
        prewarmedPageEntries.removeAll(keepingCapacity: true)
    }

    func fit(_ grid: DisplayGrid) {
        let iconSizeChanged = resolvedIconSize != grid.iconSize
        resolvedIconSize = grid.iconSize
        guard grid.columns != columns || grid.rows != rows || iconSizeChanged else { return }
        columns = grid.columns
        rows = grid.rows
        refreshItems()
    }

    func navigate(_ move: GridMove) {
        showsKeyboardSelection = true
        guard
            let next = GridNavigation.destination(
                from: selection, move: move, itemCount: items.count, columns: columns, rows: rows
            )
        else { return }
        let destinationPage = next / capacity
        guard destinationPage == page else {
            requestPage(destinationPage)
            return
        }
        selection = next
    }

    func changePage(_ delta: Int) {
        requestPage(page + delta)
    }

    func activateSelection() {
        guard items.indices.contains(selection) else { return }
        activate(items[selection])
    }

    func activate(_ item: LauncherCore.LibraryItem) {
        switch item {
        case .folder(let id): openFolderID = id
        case .application(let id):
            guard let app = record(id), !isLaunching else { return }
            isLaunching = true
            Task { @MainActor in
                defer { isLaunching = false }
                do {
                    try await launcher.open(app.url)
                    recordActivation(app.id, source: .launcher)
                    lastFailedLaunch = nil
                    launchFailure = nil
                    onDismiss?(false)
                } catch {
                    lastFailedLaunch = app
                    launchFailure =
                        "\(app.name) could not open. It may have moved or may need attention in Finder."
                }
            }
        }
    }

    func escape() {
        stopDragPaging()
        if draggedItem != nil {
            draggedItem = nil
            dropTarget = nil
        } else if !query.isEmpty {
            query = ""
        } else if openFolderID != nil {
            openFolderID = nil
        } else {
            onDismiss?(true)
        }
        focusGeneration += 1
    }

    func prepareToShow() {
        stopDragPaging()
        showsKeyboardSelection = false
        if !query.isEmpty { query = "" }
        if openFolderID != nil { openFolderID = nil }
        draggedItem = nil
        dropTarget = nil
        dropConfirmation = nil
        dropConfirmationTask?.cancel()
        dropConfirmationTask = nil
        var startCollection = preferences.startCollection
        if startCollection == .favorites && !preferences.showsFavorites { startCollection = .all }
        if startCollection == .recents && !preferences.showsRecents { startCollection = .all }
        if collection != startCollection { collection = startCollection }
        page = 0
        selection = 0
        focusGeneration += 1
        pruneRecents()
    }

    func recordActivation(_ id: String, source: ActivationSource) {
        guard isReady, !recoveryLocked else { return }
        guard
            let policy = try? RecentsPolicy(
                retentionDays: preferences.retentionDays,
                maximumCount: preferences.maximumRecentsCount,
                recordsEvents: preferences.recordsRecents,
                scope: preferences.recentsScope
            )
        else { return }
        let history = policy.recording(
            applicationID: id, at: now(), source: source,
            history: library.recents, catalogIDs: Set(recordsByID.keys),
            hiddenIDs: library.hiddenIDs)
        guard history != library.recents else { return }
        do {
            try library.apply(.replaceRecents(history))
            if collection == .recents && query.isEmpty && openFolderID == nil { refreshItems() }
            scheduleSave()
        } catch { message = "Recent history could not be updated." }
    }

    func confirmFavoriteDrop(for applicationID: String) {
        dropConfirmationTask?.cancel()
        guard let name = record(applicationID)?.name else { return }
        dropConfirmation = "Added \(name) to Favorites"
        dropConfirmationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.dropConfirmation = nil
            self?.dropConfirmationTask = nil
        }
    }

    func pruneRecents() {
        guard
            let policy = try? RecentsPolicy(
                retentionDays: preferences.retentionDays,
                maximumCount: preferences.maximumRecentsCount
            )
        else {
            return
        }
        let recent = policy.pruned(
            library.recents, now: now(), catalogIDs: Set(recordsByID.keys),
            hiddenIDs: library.hiddenIDs)
        guard recent != library.recents else { return }
        do {
            try library.apply(.replaceRecents(recent))
            refreshItems()
            scheduleSave()
        } catch { message = "Recent history could not be updated." }
    }

}
