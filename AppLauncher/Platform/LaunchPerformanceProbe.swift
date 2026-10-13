import Foundation

@MainActor
final class LaunchPerformanceProbe {
    struct Summary: Equatable, Sendable {
        let count: Int
        let p50Milliseconds: Double
        let p95Milliseconds: Double
    }

    struct IconSummary: Equatable, Sendable {
        let firstRealIconCount: Int
        let firstRealIconP50Milliseconds: Double?
        let firstRealIconP95Milliseconds: Double?
        let allVisibleIconsCount: Int
        let allVisibleIconsP50Milliseconds: Double?
        let allVisibleIconsP95Milliseconds: Double?
    }

    private static let maximumSamples = 1_000

    let enabled: Bool
    private(set) var millisecondSamples: [Double] = []
    private(set) var firstRealVisibleIconSamples: [Double] = []
    private(set) var allVisibleIconSamples: [Double] = []
    private(set) var catalogRefreshSamples: [Double] = []
    private(set) var searchUpdateSamples: [Double] = []
    var lastMilliseconds: Double? { millisecondSamples.last }
    var lastFirstRealVisibleIconMilliseconds: Double? { firstRealVisibleIconSamples.last }
    var lastAllVisibleIconsMilliseconds: Double? { allVisibleIconSamples.last }
    var lastCatalogRefreshMilliseconds: Double? { catalogRefreshSamples.last }

    private let clock = ContinuousClock()
    private var searchUpdateStart: (query: String, instant: ContinuousClock.Instant)?
    private var invocationStart: ContinuousClock.Instant?
    private var invocationID: UInt64 = 0
    private var focusRecorded = false
    private var visibleIconKeys = Set<String>()
    private var visibleIconURLPaths = Set<String>()
    private var scopeUsesURLs = false
    private var completedVisibleIconKeys = Set<String>()
    private var firstRealIconRecorded = false
    private var visibleScopeSignature: Set<String>?
    private var catalogRefreshID: UInt64 = 0
    private var catalogRefreshStarts: [UInt64: ContinuousClock.Instant] = [:]

    init(enabled: Bool) {
        self.enabled = enabled
    }

    func beginInvocation() {
        guard enabled else { return }
        invocationID &+= 1
        invocationStart = clock.now
        focusRecorded = false
        visibleIconKeys.removeAll(keepingCapacity: true)
        visibleIconURLPaths.removeAll(keepingCapacity: true)
        scopeUsesURLs = false
        completedVisibleIconKeys.removeAll(keepingCapacity: true)
        firstRealIconRecorded = false
        visibleScopeSignature = nil
    }

    /// Call only after the launcher window is visible and the native search field is first responder.
    func didFocusSearch(windowIsKey: Bool) {
        guard enabled, windowIsKey, let invocationStart, !focusRecorded else { return }
        focusRecorded = true
        let milliseconds = elapsedMilliseconds(since: invocationStart)
        append(milliseconds, to: &millisecondSamples)
        print(String(format: "invocation_ms=%.3f", milliseconds))
    }

    func beginSearchUpdate(query: String) {
        guard enabled else { return }
        searchUpdateStart = (query, clock.now)
    }

    /// The native search field consumed the query during a view update, not GPU presentation.
    func didUpdateSearch(query: String) {
        guard let start = searchUpdateStart, start.query == query else { return }
        searchUpdateStart = nil
        append(elapsedMilliseconds(since: start.instant), to: &searchUpdateSamples)
    }

    /// Registers the current page's cache keys after layout has resolved the actual icon sizes.
    /// Terminal failures count toward all-visible completion, but never toward first-real-icon.
    func beginVisibleIconScope(_ keys: Set<String>) {
        guard enabled, invocationStart != nil else { return }
        guard visibleScopeSignature != keys || scopeUsesURLs else { return }
        visibleScopeSignature = keys
        scopeUsesURLs = false
        visibleIconKeys = keys
        visibleIconURLPaths.removeAll(keepingCapacity: true)
        completedVisibleIconKeys.removeAll(keepingCapacity: true)
        firstRealIconRecorded = false
        if keys.isEmpty, let invocationStart {
            let milliseconds = elapsedMilliseconds(since: invocationStart)
            append(milliseconds, to: &allVisibleIconSamples)
            print(String(format: "icons_visible_complete_ms=%.3f count=0", milliseconds))
        }
    }

    func beginVisibleIconScope(urls: Set<URL>) {
        guard enabled, invocationStart != nil else { return }
        let paths = Set(urls.map(\.standardizedFileURL.path))
        guard visibleScopeSignature != paths || !scopeUsesURLs else { return }
        visibleScopeSignature = paths
        scopeUsesURLs = true
        visibleIconKeys.removeAll(keepingCapacity: true)
        visibleIconURLPaths = paths
        completedVisibleIconKeys.removeAll(keepingCapacity: true)
        firstRealIconRecorded = false
        if paths.isEmpty, let invocationStart {
            let milliseconds = elapsedMilliseconds(since: invocationStart)
            append(milliseconds, to: &allVisibleIconSamples)
            print(String(format: "icons_visible_complete_ms=%.3f count=0", milliseconds))
        }
    }

    func iconDidComplete(_ completion: ApplicationIconLoadCompletion) {
        guard enabled, let invocationStart else { return }
        let completionKey: String
        if scopeUsesURLs {
            completionKey = completion.url.standardizedFileURL.path
            guard visibleIconURLPaths.contains(completionKey) else { return }
        } else {
            completionKey = completion.key
            guard visibleIconKeys.contains(completionKey) else { return }
        }
        guard completedVisibleIconKeys.insert(completionKey).inserted else { return }

        let milliseconds = elapsedMilliseconds(since: invocationStart)
        if completion.loaded, !firstRealIconRecorded {
            firstRealIconRecorded = true
            append(milliseconds, to: &firstRealVisibleIconSamples)
            print(String(format: "icon_first_visible_ms=%.3f", milliseconds))
        }
        let expectedCount = scopeUsesURLs ? visibleIconURLPaths.count : visibleIconKeys.count
        guard completedVisibleIconKeys.count == expectedCount else { return }
        append(milliseconds, to: &allVisibleIconSamples)
        print(
            String(
                format: "icons_visible_complete_ms=%.3f count=%lu",
                milliseconds,
                expectedCount
            ))
    }

    func beginCatalogRefresh() -> UInt64? {
        guard enabled else { return nil }
        catalogRefreshID &+= 1
        let id = catalogRefreshID
        catalogRefreshStarts[id] = clock.now
        return id
    }

    func endCatalogRefresh(_ id: UInt64?, succeeded: Bool) {
        guard enabled, let id, let start = catalogRefreshStarts.removeValue(forKey: id) else {
            return
        }
        guard succeeded else { return }
        let milliseconds = elapsedMilliseconds(since: start)
        append(milliseconds, to: &catalogRefreshSamples)
        print(String(format: "catalog_refresh_ms=%.3f", milliseconds))
    }

    func summary() -> Summary? {
        guard !millisecondSamples.isEmpty else { return nil }
        let sorted = millisecondSamples.sorted()
        return Summary(
            count: sorted.count,
            p50Milliseconds: Self.percentile(0.50, sorted: sorted),
            p95Milliseconds: Self.percentile(0.95, sorted: sorted)
        )
    }

    func iconSummary() -> IconSummary? {
        guard !firstRealVisibleIconSamples.isEmpty || !allVisibleIconSamples.isEmpty else {
            return nil
        }
        let first = firstRealVisibleIconSamples.sorted()
        let all = allVisibleIconSamples.sorted()
        return IconSummary(
            firstRealIconCount: first.count,
            firstRealIconP50Milliseconds: first.isEmpty
                ? nil : Self.percentile(0.50, sorted: first),
            firstRealIconP95Milliseconds: first.isEmpty
                ? nil : Self.percentile(0.95, sorted: first),
            allVisibleIconsCount: all.count,
            allVisibleIconsP50Milliseconds: all.isEmpty
                ? nil : Self.percentile(0.50, sorted: all),
            allVisibleIconsP95Milliseconds: all.isEmpty
                ? nil : Self.percentile(0.95, sorted: all)
        )
    }

    private func append(_ value: Double, to samples: inout [Double]) {
        samples.append(value)
        if samples.count > Self.maximumSamples {
            samples.removeFirst(samples.count - Self.maximumSamples)
        }
    }

    private func elapsedMilliseconds(since start: ContinuousClock.Instant) -> Double {
        let duration = start.duration(to: clock.now)
        let components = duration.components
        return
            (Double(components.seconds) * 1_000)
            + (Double(components.attoseconds) / 1_000_000_000_000_000)
    }

    private static func percentile(_ percentile: Double, sorted samples: [Double]) -> Double {
        let index = max(0, Int(ceil(percentile * Double(samples.count))) - 1)
        return samples[min(index, samples.count - 1)]
    }
}

struct ApplicationIconBenchmarkResult: Codable, Sendable {
    let catalogCount: Int
    let oneWorkerSamplesMilliseconds: [Double]
    let twoWorkerSamplesMilliseconds: [Double]
    let threeWorkerSamplesMilliseconds: [Double]
    let oneWorkerMedianMilliseconds: Double
    let twoWorkerMedianMilliseconds: Double
    let threeWorkerMedianMilliseconds: Double
    let improvementPercent: Double
    let totalCostLimitBytes: Int

    var meetsImprovementGate: Bool { improvementPercent >= 30 }
}

struct LauncherInvocationBenchmarkResult: Codable, Sendable {
    let coldMilliseconds: Double
    let warmSamplesMilliseconds: [Double]
    let warmP50Milliseconds: Double
    let warmP95Milliseconds: Double
    let searchRecordCount: Int
    let searchUpdateSamplesMilliseconds: [Double]
}

@MainActor
enum ApplicationIconBenchmark {
    enum Error: Swift.Error {
        case insufficientApplications(Int)
        case timedOut(workerCount: Int)
    }

    static func run(outputURL: URL) async throws -> ApplicationIconBenchmarkResult {
        let catalog = Array(try applicationURLs().prefix(60))
        guard catalog.count >= 20 else { throw Error.insufficientApplications(catalog.count) }

        _ = try await measure(catalog, workerCount: 3)
        var oneWorker: [Double] = []
        var twoWorkers: [Double] = []
        var threeWorkers: [Double] = []
        for _ in 0..<3 {
            oneWorker.append(try await measure(catalog, workerCount: 1))
            twoWorkers.append(try await measure(catalog, workerCount: 2))
            threeWorkers.append(try await measure(catalog, workerCount: 3))
        }
        let oneMedian = median(oneWorker)
        let twoMedian = median(twoWorkers)
        let threeMedian = median(threeWorkers)
        let result = ApplicationIconBenchmarkResult(
            catalogCount: catalog.count,
            oneWorkerSamplesMilliseconds: oneWorker,
            twoWorkerSamplesMilliseconds: twoWorkers,
            threeWorkerSamplesMilliseconds: threeWorkers,
            oneWorkerMedianMilliseconds: oneMedian,
            twoWorkerMedianMilliseconds: twoMedian,
            threeWorkerMedianMilliseconds: threeMedian,
            improvementPercent: (oneMedian - twoMedian) / oneMedian * 100,
            totalCostLimitBytes: 32 * 1_024 * 1_024
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(result).write(to: outputURL, options: .atomic)
        return result
    }

    private static func applicationURLs() throws -> [URL] {
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
        ]
        return try roots.flatMap {
            try FileManager.default.contentsOfDirectory(
                at: $0, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        }.filter { $0.pathExtension.lowercased() == "app" }
            .sorted { $0.path < $1.path }
    }

    private static func measure(_ urls: [URL], workerCount: Int) async throws -> Double {
        let cache = ApplicationIconCache(workerCount: workerCount)
        cache.updatePriorityScope(currentPage: urls, folderThumbnails: [], adjacentPage: [])
        let clock = ContinuousClock()
        let start = clock.now
        let entries = urls.map {
            cache.entry(for: $0, size: 64, priority: .visiblePage)
        }
        let deadline = start.advanced(by: .seconds(15))
        while !entries.allSatisfy(\.isLoaded), clock.now < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        guard entries.allSatisfy(\.isLoaded) else { throw Error.timedOut(workerCount: workerCount) }
        let components = start.duration(to: clock.now).components
        return Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
    }

    private static func median(_ values: [Double]) -> Double {
        values.sorted()[values.count / 2]
    }
}
