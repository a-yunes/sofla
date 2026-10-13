import Foundation
import LauncherCore
import Testing

@testable import LauncherInfrastructure

struct CatalogProvenanceTests {
    @Test
    func externalSymlinkSurvivesAnUnavailableRootAndCacheRoundTrip() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let rootURL = directory.appending(path: "Selected")
        let otherRootURL = directory.appending(path: "Other")
        let application = directory.appending(path: "External/Editor.app")
        let contents = application.appending(path: "Contents")
        for url in [rootURL, otherRootURL, contents] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        let metadata = try PropertyListSerialization.data(
            fromPropertyList: [
                "CFBundleName": "Editor", "CFBundleIdentifier": "example.editor",
                "CFBundlePackageType": "APPL",
            ], format: .xml, options: 0)
        try metadata.write(to: contents.appending(path: "Info.plist"))
        for root in [rootURL, otherRootURL] {
            try FileManager.default.createSymbolicLink(
                at: root.appending(path: "Editor.app"), withDestinationURL: application)
        }
        let roots = [rootURL, otherRootURL].map {
            ApplicationScanRoot(id: $0.absoluteString, url: $0, kind: .custom)
        }
        let scanner = ApplicationScanner()
        let initial = try await scanner.scan(roots: roots)
        #expect(initial.records.count == 1)
        let target = try #require(initial.records.first?.url.path)
        #expect(
            initial.discoveryRootsByPath[target]
                == Set(roots.map { $0.url.standardizedFileURL.path }))
        let catalog = ApplicationCatalog(
            records: initial.records, discoveryRootsByPath: initial.discoveryRootsByPath)
        let cached = try JSONDecoder().decode(
            ApplicationCatalog.self, from: JSONEncoder().encode(catalog))
        try CatalogCacheValidator.validate(cached)
        try FileManager.default.removeItem(at: rootURL)
        try FileManager.default.removeItem(at: otherRootURL)
        let unavailable = try await scanner.scan(roots: roots)

        let retained = CatalogScanMerger.reconcile(
            previous: cached.records, scan: unavailable,
            previousDiscoveryRootsByPath: cached.discoveryRootsByPath)

        #expect(retained.reconciliation.records == initial.records)
        #expect(retained.discoveryRootsByPath == initial.discoveryRootsByPath)
        let removed = CatalogScanMerger.reconcile(
            previous: cached.records, scan: ApplicationScanResult(records: [], roots: []),
            previousDiscoveryRootsByPath: cached.discoveryRootsByPath)
        #expect(removed.reconciliation.records.isEmpty)
        #expect(removed.discoveryRootsByPath.isEmpty)

        try FileManager.default.createDirectory(at: otherRootURL, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: otherRootURL.appending(path: "Editor.app"), withDestinationURL: application)
        let recovered = try await scanner.scan(roots: [roots[1]])
        let merged = CatalogScanMerger.reconcile(
            previous: retained.reconciliation.records, scan: recovered,
            previousDiscoveryRootsByPath: retained.discoveryRootsByPath)
        #expect(merged.reconciliation.records == initial.records)
        #expect(merged.discoveryRootsByPath[target] == [otherRootURL.standardizedFileURL.path])
    }
}
