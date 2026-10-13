import Foundation
import LauncherCore

/// Merges canonical scan snapshots without filesystem work. Discovery roots survive temporary
/// outages even when an application was found through a symlink outside those roots.
public enum CatalogScanMerger {
    public static func reconcile(
        previous: [ApplicationRecord],
        scan: ApplicationScanResult,
        previousDiscoveryRootsByPath: [String: Set<String>] = [:],
        retainOutsideRoots: Bool = false
    ) -> (reconciliation: CatalogReconciliation, discoveryRootsByPath: [String: Set<String>]) {
        let scannedRoots = scan.roots.map { outcome in
            (outcome, outcome.canonicalRootURL.standardizedFileURL.pathComponents)
        }
        let incompleteRootIDs = Set(
            scan.roots.filter { $0.completeness != .complete }.map {
                $0.root.url.standardizedFileURL.path
            })
        var candidates = scan.records
        let scannedURLs = Set(scan.records.map { $0.url.standardizedFileURL })
        let previousByBundle = Dictionary(grouping: previous, by: \.bundleIdentifier)
        let scannedByBundle = Dictionary(grouping: scan.records, by: \.bundleIdentifier)

        for record in previous {
            let recordURL = record.url.standardizedFileURL
            guard !scannedURLs.contains(recordURL) else { continue }
            if let bundleIdentifier = record.bundleIdentifier,
                previousByBundle[bundleIdentifier]?.count == 1,
                scannedByBundle[bundleIdentifier]?.count == 1
            {
                continue
            }
            let knownRoots = previousDiscoveryRootsByPath[recordURL.path] ?? []
            let matchingRoots = scannedRoots.filter { _, components in
                recordURL.pathComponents.starts(with: components)
            }
            let retain =
                knownRoots.isEmpty
                ? matchingRoots.contains(where: { $0.0.completeness != .complete })
                    || (matchingRoots.isEmpty && retainOutsideRoots)
                : !knownRoots.isDisjoint(with: incompleteRootIDs)
            if retain { candidates.append(record) }
        }

        let reconciliation = CatalogReconciler.reconcile(previous: previous, discovered: candidates)
        var discoveryRootsByPath: [String: Set<String>] = [:]
        for record in reconciliation.records {
            let url = record.url.standardizedFileURL.path
            let retainedRoots = (previousDiscoveryRootsByPath[url] ?? [])
                .intersection(incompleteRootIDs)
            let roots = retainedRoots.union(scan.discoveryRootsByPath[url] ?? [])
            if !roots.isEmpty { discoveryRootsByPath[url] = roots }
        }
        return (reconciliation, discoveryRootsByPath)
    }
}
