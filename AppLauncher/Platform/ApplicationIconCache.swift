import AppKit
import LauncherCore
import Observation

@MainActor
@Observable
final class ApplicationIconEntry {
    private(set) var image: NSImage
    private(set) var isLoaded = false
    private(set) var hasRealImage = false
    @ObservationIgnored private var isDiscarded = false
    @ObservationIgnored private var waiters: [UUID: CheckedContinuation<Bool, Never>] = [:]

    init(image: NSImage) {
        self.image = image
    }

    func complete(with image: NSImage?) {
        if let image {
            self.image = image
            hasRealImage = true
        }
        isLoaded = true
        let pending = waiters.values
        waiters.removeAll()
        for waiter in pending { waiter.resume(returning: true) }
    }

    func discard() {
        isDiscarded = true
        let pending = waiters.values
        waiters.removeAll()
        for waiter in pending { waiter.resume(returning: false) }
    }

    func waitUntilLoaded(timeout: Duration) async -> Bool {
        guard !isDiscarded else { return false }
        guard !isLoaded else { return true }
        let id = UUID()
        let timeoutTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: timeout)
                guard let waiter = self?.waiters.removeValue(forKey: id) else { return }
                waiter.resume(returning: false)
            } catch {
                guard let waiter = self?.waiters.removeValue(forKey: id) else { return }
                waiter.resume(returning: false)
            }
        }
        let loaded: Bool = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                if isLoaded || Task.isCancelled {
                    continuation.resume(returning: isLoaded)
                } else {
                    waiters[id] = continuation
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let waiter = self?.waiters.removeValue(forKey: id) else { return }
                waiter.resume(returning: false)
            }
        }
        timeoutTask.cancel()
        return loaded
    }
}

nonisolated protocol ApplicationIconLoading: Sendable {
    func load(url: URL, pixelLength: Int) async -> CGImage?
}

enum ApplicationIconRequestPriority: Int, Comparable, Sendable {
    case visiblePage = 0
    case folderThumbnail = 1
    case adjacentPage = 2

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

struct ApplicationIconLoadCompletion: Equatable, Sendable {
    let key: String
    let url: URL
    let priority: ApplicationIconRequestPriority
    let loaded: Bool
}

/// A bounded, regenerable cache that never performs icon I/O from a view body.
@MainActor
public final class ApplicationIconCache {
    enum WaitResult {
        case ready
        case timedOut
        case cancelled
    }
    private static let maximumWorkerCount = 3
    private static let defaultWorkerCount = 2
    private static let maximumVisibleIconRequests =
        GridConfiguration.columnRange.upperBound * GridConfiguration.rowRange.upperBound * 9

    private struct Request {
        let key: NSString
        let stringKey: String
        let url: URL
        let pointSize: CGFloat
        let pixelLength: Int
        let generation: UInt64
        let keyGeneration: UInt64
        let priority: ApplicationIconRequestPriority
        let sequence: UInt64
        let entry: ApplicationIconEntry

        func replacing(priority: ApplicationIconRequestPriority) -> Self {
            Request(
                key: key,
                stringKey: stringKey,
                url: url,
                pointSize: pointSize,
                pixelLength: pixelLength,
                generation: generation,
                keyGeneration: keyGeneration,
                priority: priority,
                sequence: sequence,
                entry: entry
            )
        }
    }

    private let cache = NSCache<NSString, ApplicationIconEntry>()
    private let loader: any ApplicationIconLoading
    private let scale: CGFloat = 2
    private let workerCount: Int
    private let maximumPendingCount: Int
    private let maximumKnownKeyCount: Int
    private var generation: UInt64 = 0
    private var nextKeyGeneration: UInt64 = 0
    private var nextSequence: UInt64 = 0
    private var pending: [Request] = []
    private var pendingKeys = Set<String>()
    private var inFlightEntries: [String: ApplicationIconEntry] = [:]
    private var activeRequests: [UUID: Request] = [:]
    private var activeTasks: [UUID: Task<Void, Never>] = [:]
    private var knownKeys: [String: URL] = [:]
    private var keyGenerations: [String: UInt64] = [:]
    private var strongVisibleEntries: [String: ApplicationIconEntry] = [:]
    private var priorityByURLPath: [String: ApplicationIconRequestPriority] = [:]
    private var visibleURLPaths = Set<String>()
    private var retainedURLPaths = Set<String>()

    var onLoadCompletion: (@MainActor (ApplicationIconLoadCompletion) -> Void)?
    var onVisibleScopeChanged: (@MainActor (Set<URL>) -> Void)?

    public init(
        countLimit: Int = 256,
        totalCostLimit: Int = 32 * 1_024 * 1_024,
        workerCount: Int? = nil
    ) {
        self.loader = ApplicationIconLoader()
        let boundedCount = max(1, countLimit)
        cache.countLimit = boundedCount
        cache.totalCostLimit = max(1, totalCostLimit)
        let requestedWorkerCount = workerCount ?? Self.configuredWorkerCount()
        self.workerCount = min(max(requestedWorkerCount, 1), Self.maximumWorkerCount)
        maximumPendingCount = max(boundedCount, Self.maximumVisibleIconRequests)
        maximumKnownKeyCount = maximumPendingCount + Self.maximumWorkerCount
    }

    init(
        countLimit: Int = 256,
        totalCostLimit: Int = 32 * 1_024 * 1_024,
        workerCount: Int = 3,
        pendingLimit: Int? = nil,
        loader: any ApplicationIconLoading
    ) {
        self.loader = loader
        let boundedCount = max(1, countLimit)
        cache.countLimit = boundedCount
        cache.totalCostLimit = max(1, totalCostLimit)
        self.workerCount = min(max(workerCount, 1), Self.maximumWorkerCount)
        maximumPendingCount = max(
            1, pendingLimit ?? max(boundedCount, Self.maximumVisibleIconRequests))
        maximumKnownKeyCount = maximumPendingCount + Self.maximumWorkerCount
    }

    public func image(for applicationURL: URL, size requestedSize: CGFloat) -> NSImage {
        entry(for: applicationURL, size: requestedSize).image
    }

    func entry(
        for applicationURL: URL,
        size requestedSize: CGFloat,
        priority: ApplicationIconRequestPriority? = nil
    ) -> ApplicationIconEntry {
        let size = min(max(requestedSize.isFinite ? requestedSize : 1, 1), 512)
        let pixelLength = max(1, Int((size * scale).rounded(.up)))
        let standardizedURL = applicationURL.standardizedFileURL
        let key = (standardizedURL.path + "|" + String(pixelLength)) as NSString
        let stringKey = key as String
        let requestPriority = effectivePriority(
            explicit: priority, url: standardizedURL, requestedSize: size)

        if let entry = strongVisibleEntries[stringKey] {
            if !entry.isLoaded {
                enqueue(
                    key: key, url: standardizedURL, size: size, entry: entry,
                    priority: requestPriority)
            }
            return entry
        }
        if let entry = cache.object(forKey: key) {
            retainIfVisible(entry, key: stringKey, url: standardizedURL)
            if !entry.isLoaded {
                enqueue(
                    key: key, url: standardizedURL, size: size, entry: entry,
                    priority: requestPriority)
            }
            return entry
        }
        if let entry = inFlightEntries[stringKey] {
            retainIfVisible(entry, key: stringKey, url: standardizedURL)
            enqueue(
                key: key, url: standardizedURL, size: size, entry: entry, priority: requestPriority)
            cache.setObject(entry, forKey: key, cost: pixelLength * pixelLength * 4)
            return entry
        }

        let entry = ApplicationIconEntry(image: Self.placeholder(pointSize: size))
        cache.setObject(entry, forKey: key, cost: pixelLength * pixelLength * 4)
        retainIfVisible(entry, key: stringKey, url: standardizedURL)
        knownKeys[stringKey] = standardizedURL
        if keyGenerations[stringKey] == nil { keyGenerations[stringKey] = nextKeyGeneration }
        enqueue(
            key: key, url: standardizedURL, size: size, entry: entry, priority: requestPriority)
        return entry
    }

    func prefetch(
        url: URL,
        size: CGFloat,
        priority: ApplicationIconRequestPriority
    ) -> ApplicationIconEntry {
        entry(for: url, size: size, priority: priority)
    }

    /// Updates URL-level priority and ownership for the currently visible page.
    /// The cache key still includes pixel length, so the actual size is supplied by each view.
    func updatePriorityScope(
        currentPage: [URL], folderThumbnails: [URL], adjacentPage: [URL]
    ) {
        let currentPaths = Set(currentPage.map(Self.normalizedPath))
        let thumbnailPaths = Set(folderThumbnails.map(Self.normalizedPath))
        let adjacentPaths = Set(adjacentPage.map(Self.normalizedPath))
        visibleURLPaths = currentPaths.union(thumbnailPaths)
        retainedURLPaths = visibleURLPaths.union(adjacentPaths)

        var priorities: [String: ApplicationIconRequestPriority] = [:]
        for path in adjacentPaths { priorities[path] = .adjacentPage }
        for path in thumbnailPaths { priorities[path] = .folderThumbnail }
        for path in currentPaths { priorities[path] = .visiblePage }
        priorityByURLPath = priorities
        let relevantPaths = currentPaths.union(thumbnailPaths).union(adjacentPaths)
        let obsoleteKeys = Set(
            (pending + Array(activeRequests.values)).filter {
                !relevantPaths.contains(Self.normalizedPath($0.url))
            }.map(\.stringKey))
        reprioritizePending()
        invalidate(keys: obsoleteKeys)

        let keysToRelease = strongVisibleEntries.keys.filter {
            !retainedURLPaths.contains(path(for: $0))
        }
        for key in keysToRelease {
            strongVisibleEntries.removeValue(forKey: key)
        }
        for (key, url) in knownKeys where retainedURLPaths.contains(Self.normalizedPath(url)) {
            if let entry = cache.object(forKey: key as NSString) {
                strongVisibleEntries[key] = entry
            } else if let entry = inFlightEntries[key] {
                strongVisibleEntries[key] = entry
            }
        }
        onVisibleScopeChanged?(Set(currentPage + folderThumbnails))
        startNextIfNeeded()
    }

    func removeAll() {
        generation &+= 1
        nextKeyGeneration &+= 1
        for task in activeTasks.values { task.cancel() }
        pending.removeAll(keepingCapacity: true)
        pendingKeys.removeAll(keepingCapacity: true)
        inFlightEntries.removeAll(keepingCapacity: true)
        strongVisibleEntries.removeAll(keepingCapacity: true)
        knownKeys.removeAll(keepingCapacity: true)
        keyGenerations.removeAll(keepingCapacity: true)
        visibleURLPaths.removeAll(keepingCapacity: true)
        retainedURLPaths.removeAll(keepingCapacity: true)
        priorityByURLPath.removeAll(keepingCapacity: true)
        cache.removeAllObjects()
        // Keep active requests and tasks counted until their cooperative loaders return. This
        // preserves the hard worker bound even if a native call cannot be interrupted midway.
    }

    func invalidate(changedPaths: [URL], requiresFullInvalidation: Bool = false) {
        if requiresFullInvalidation {
            removeAll()
            return
        }
        let normalizedPaths = changedPaths.map(Self.normalizedPath)
        guard !normalizedPaths.isEmpty else { return }
        let affectedKeys = Set(
            knownKeys.compactMap { key, url in
                normalizedPaths.contains(where: { Self.isContained($0, in: url) }) ? key : nil
            })
        invalidate(keys: affectedKeys)
    }

    func completeAsTerminalFallback(_ entries: [ApplicationIconEntry]) {
        let entryIDs = Set(entries.map(ObjectIdentifier.init))
        let keys = knownKeys.keys.filter { key in
            if let entry = cache.object(forKey: key as NSString),
                entryIDs.contains(ObjectIdentifier(entry))
            {
                return true
            }
            if let entry = inFlightEntries[key], entryIDs.contains(ObjectIdentifier(entry)) {
                return true
            }
            return false
        }
        for key in keys {
            guard
                let entry = cache.object(forKey: key as NSString) ?? inFlightEntries[key],
                let url = knownKeys[key]
            else { continue }
            nextKeyGeneration &+= 1
            keyGenerations[key] = nextKeyGeneration
            if pending.contains(where: { $0.stringKey == key }) {
                pending.removeAll { $0.stringKey == key }
                pendingKeys.remove(key)
            }
            for (requestID, request) in activeRequests where request.stringKey == key {
                activeTasks[requestID]?.cancel()
            }
            inFlightEntries.removeValue(forKey: key)
            if !entry.isLoaded {
                entry.complete(with: nil)
                onLoadCompletion?(
                    ApplicationIconLoadCompletion(
                        key: key,
                        url: url,
                        priority: priorityByURLPath[Self.normalizedPath(url)] ?? .adjacentPage,
                        loaded: false
                    ))
            }
        }
        startNextIfNeeded()
    }

    func containsCurrentEntries(_ entries: [ApplicationIconEntry]) -> Bool {
        let currentEntries = knownKeys.keys.compactMap { key in
            strongVisibleEntries[key]
                ?? cache.object(forKey: key as NSString)
                ?? inFlightEntries[key]
        }
        let currentEntryIDs = Set(currentEntries.map(ObjectIdentifier.init))
        return entries.allSatisfy { currentEntryIDs.contains(ObjectIdentifier($0)) }
    }

    func waitUntilTerminal(
        _ entries: [ApplicationIconEntry], timeout: Duration = .seconds(3)
    ) async -> WaitResult {
        if entries.allSatisfy(\.isLoaded) { return .ready }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        for entry in entries where !entry.isLoaded {
            if Task.isCancelled { return .cancelled }
            let now = clock.now
            guard now < deadline else { return .timedOut }
            let loaded = await entry.waitUntilLoaded(timeout: now.duration(to: deadline))
            if Task.isCancelled { return .cancelled }
            if !loaded { return .timedOut }
        }
        return .ready
    }

    func removeAll(
        ifCatalogChangedFrom previous: [ApplicationRecord], to current: [ApplicationRecord]
    ) {
        let previousByID = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0) })
        let currentByID = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        var changedURLs = Set<URL>()
        for id in Set(previousByID.keys).union(currentByID.keys) {
            guard previousByID[id] != currentByID[id] else { continue }
            if let url = previousByID[id]?.url { changedURLs.insert(url.standardizedFileURL) }
            if let url = currentByID[id]?.url { changedURLs.insert(url.standardizedFileURL) }
        }

        // A reconciliation can retain an installation's identity while its bundle identifier
        // or URL changes. Compare URL groups as well so a path update invalidates the old key.
        let previousByURL = Dictionary(grouping: previous, by: { $0.url.standardizedFileURL })
        let currentByURL = Dictionary(grouping: current, by: { $0.url.standardizedFileURL })
        for url in Set(previousByURL.keys).union(currentByURL.keys)
        where previousByURL[url] != currentByURL[url] {
            changedURLs.insert(url)
        }
        invalidate(changedPaths: Array(changedURLs))
    }

    private func enqueue(
        key: NSString,
        url: URL,
        size: CGFloat,
        entry: ApplicationIconEntry,
        priority: ApplicationIconRequestPriority
    ) {
        let stringKey = key as String
        let keyGeneration = keyGenerations[stringKey] ?? nextKeyGeneration
        if keyGenerations[stringKey] == nil { keyGenerations[stringKey] = keyGeneration }

        if let index = pending.firstIndex(where: { $0.stringKey == stringKey }) {
            let existing = pending[index]
            if priority < existing.priority {
                pending[index] = existing.replacing(priority: priority)
            }
            return
        }
        if activeRequests.values.contains(where: {
            $0.stringKey == stringKey && $0.entry === entry
        }) {
            return
        }
        if pending.count >= maximumPendingCount {
            guard
                let lowestIndex = pending.indices.max(by: { lhs, rhs in
                    pending[lhs].priority == pending[rhs].priority
                        ? pending[lhs].sequence < pending[rhs].sequence
                        : pending[lhs].priority < pending[rhs].priority
                })
            else { return }
            let lowest = pending[lowestIndex]
            guard priority < lowest.priority else { return }
            pending.remove(at: lowestIndex)
            pendingKeys.remove(lowest.stringKey)
            inFlightEntries.removeValue(forKey: lowest.stringKey)
        }

        nextSequence &+= 1
        pendingKeys.insert(stringKey)
        inFlightEntries[stringKey] = entry
        knownKeys[stringKey] = url
        pending.append(
            Request(
                key: key,
                stringKey: stringKey,
                url: url,
                pointSize: size,
                pixelLength: max(1, Int((size * scale).rounded(.up))),
                generation: generation,
                keyGeneration: keyGeneration,
                priority: priority,
                sequence: nextSequence,
                entry: entry
            ))
        trimKnownKeys()
        startNextIfNeeded()
    }

    private func retainIfVisible(
        _ entry: ApplicationIconEntry,
        key: String,
        url: URL
    ) {
        guard retainedURLPaths.contains(Self.normalizedPath(url)) else { return }
        strongVisibleEntries[key] = entry
    }

    private func startNextIfNeeded() {
        while activeRequests.count < workerCount, !pending.isEmpty {
            pending.sort {
                if $0.priority != $1.priority { return $0.priority < $1.priority }
                return $0.sequence < $1.sequence
            }
            let request = pending.removeFirst()
            pendingKeys.remove(request.stringKey)
            let requestID = UUID()
            activeRequests[requestID] = request
            let task = Task(priority: .userInitiated) { [weak self] in
                let result = await self?.loader.load(
                    url: request.url,
                    pixelLength: request.pixelLength
                )
                guard let self else { return }
                self.complete(requestID: requestID, result: result, cancelled: Task.isCancelled)
            }
            activeTasks[requestID] = task
        }
    }

    private func complete(requestID: UUID, result: CGImage?, cancelled: Bool) {
        guard let request = activeRequests.removeValue(forKey: requestID) else {
            activeTasks.removeValue(forKey: requestID)
            return
        }
        activeTasks.removeValue(forKey: requestID)
        if inFlightEntries[request.stringKey] === request.entry {
            inFlightEntries.removeValue(forKey: request.stringKey)
        }
        let currentKeyGeneration = keyGenerations[request.stringKey] ?? request.keyGeneration
        let isCurrent =
            !cancelled
            && request.generation == generation
            && request.keyGeneration == currentKeyGeneration
        if isCurrent {
            request.entry.complete(
                with: result.map {
                    NSImage(
                        cgImage: $0,
                        size: NSSize(width: request.pointSize, height: request.pointSize)
                    )
                })
            onLoadCompletion?(
                ApplicationIconLoadCompletion(
                    key: request.stringKey,
                    url: request.url,
                    priority: request.priority,
                    loaded: result != nil
                ))
        }

        if !knownKeys.keys.contains(request.stringKey),
            !activeRequests.values.contains(where: {
                $0.stringKey == request.stringKey
            })
        {
            keyGenerations.removeValue(forKey: request.stringKey)
        }
        startNextIfNeeded()
        trimKnownKeys()
    }

    private func invalidate(keys: Set<String>) {
        guard !keys.isEmpty else { return }
        for key in keys {
            nextKeyGeneration &+= 1
            keyGenerations[key] = nextKeyGeneration
            (strongVisibleEntries[key] ?? cache.object(forKey: key as NSString)
                ?? inFlightEntries[key])?.discard()
            cache.removeObject(forKey: key as NSString)
            strongVisibleEntries.removeValue(forKey: key)
            knownKeys.removeValue(forKey: key)
            inFlightEntries.removeValue(forKey: key)
            if let index = pending.firstIndex(where: { $0.stringKey == key }) {
                pending.remove(at: index)
                pendingKeys.remove(key)
            }
            for (requestID, request) in activeRequests where request.stringKey == key {
                request.entry.discard()
                activeTasks[requestID]?.cancel()
            }
            if !activeRequests.values.contains(where: { $0.stringKey == key }) {
                keyGenerations.removeValue(forKey: key)
            }
        }
        startNextIfNeeded()
    }

    private func reprioritizePending() {
        for index in pending.indices {
            let request = pending[index]
            let priority = effectivePriority(
                explicit: nil, url: request.url, requestedSize: request.pointSize)
            if priority != request.priority {
                pending[index] = request.replacing(priority: priority)
            }
        }
    }

    private func trimKnownKeys() {
        let excess = knownKeys.count - maximumKnownKeyCount
        guard excess > 0 else { return }
        let protectedKeys = Set(
            activeRequests.values.map(\.stringKey)
                + pending.map(\.stringKey)
                + Array(strongVisibleEntries.keys))
        let removable = knownKeys.keys.filter {
            !protectedKeys.contains($0) && cache.object(forKey: $0 as NSString) == nil
        }
        for key in removable.prefix(excess) {
            knownKeys.removeValue(forKey: key)
            keyGenerations.removeValue(forKey: key)
        }
    }

    private func effectivePriority(
        explicit: ApplicationIconRequestPriority?,
        url: URL,
        requestedSize: CGFloat
    ) -> ApplicationIconRequestPriority {
        if let explicit { return explicit }
        if requestedSize < 40 { return .folderThumbnail }
        return priorityByURLPath[Self.normalizedPath(url)] ?? .adjacentPage
    }

    private func path(for key: String) -> String {
        knownKeys[key].map(Self.normalizedPath) ?? key.components(separatedBy: "|").first ?? key
    }

    private static func normalizedPath(_ url: URL) -> String {
        url.standardizedFileURL.path
    }

    private static func isContained(_ childPath: String, in bundleURL: URL) -> Bool {
        let bundlePath = normalizedPath(bundleURL)
        guard childPath == bundlePath else {
            let prefix = bundlePath.hasSuffix("/") ? bundlePath : bundlePath + "/"
            return childPath.hasPrefix(prefix)
        }
        return true
    }

    private static func configuredWorkerCount() -> Int {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--icon-workers"),
            arguments.indices.contains(index + 1),
            let value = Int(arguments[index + 1])
        else { return Self.defaultWorkerCount }
        return min(max(value, 1), Self.maximumWorkerCount)
    }

    private static func placeholder(pointSize: CGFloat) -> NSImage {
        let image =
            NSImage(systemSymbolName: "app", accessibilityDescription: nil)
            ?? NSImage(size: NSSize(width: pointSize, height: pointSize))
        let placeholder = image.copy() as? NSImage ?? image
        placeholder.size = NSSize(width: pointSize, height: pointSize)
        return placeholder
    }
}

private struct ApplicationIconLoader: ApplicationIconLoading {
    @concurrent
    func load(url: URL, pixelLength: Int) async -> CGImage? {
        guard !Task.isCancelled else { return nil }
        let source = NSWorkspace.shared.icon(forFile: url.path)
        guard
            !Task.isCancelled,
            let representation = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: pixelLength,
                pixelsHigh: pixelLength,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            ),
            let context = NSGraphicsContext(bitmapImageRep: representation)
        else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        source.draw(
            in: NSRect(x: 0, y: 0, width: pixelLength, height: pixelLength),
            from: .zero,
            operation: .copy,
            fraction: 1
        )
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return representation.cgImage
    }
}
