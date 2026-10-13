import Foundation
import LauncherCore
import Testing

@testable import LauncherInfrastructure

struct CatalogScanMergerTests {
    @Test
    func completeRootRemovesMissingApplication() {
        let root = scanRoot("/Applications")
        let previous = record("old", at: "/Applications/Removed.app")
        let scan = ApplicationScanResult(
            records: [],
            roots: [outcome(root, .complete)]
        )

        let result = CatalogScanMerger.reconcile(previous: [previous], scan: scan)

        #expect(result.reconciliation.records.isEmpty)
        #expect(result.reconciliation.removedIDs == ["old"])
    }

    @Test
    func unavailableRootRetainsItsPreviousApplications() {
        let root = scanRoot("/Volumes/Offline/Applications")
        let previous = record("stable", at: "/Volumes/Offline/Applications/Editor.app")
        let scan = ApplicationScanResult(
            records: [],
            roots: [outcome(root, .unavailable)]
        )

        let result = CatalogScanMerger.reconcile(previous: [previous], scan: scan)

        #expect(result.reconciliation.records == [previous])
        #expect(result.reconciliation.removedIDs.isEmpty)
    }

    @Test
    func recordOutsideConfiguredRootsIsRemoved() {
        let configured = scanRoot("/Applications")
        let oldCustomRootRecord = record("old-custom", at: "/Volumes/Removed/Tool.app")
        let scan = ApplicationScanResult(
            records: [],
            roots: [outcome(configured, .complete)]
        )

        let result = CatalogScanMerger.reconcile(previous: [oldCustomRootRecord], scan: scan)

        #expect(result.reconciliation.records.isEmpty)
        #expect(result.reconciliation.removedIDs == ["old-custom"])
    }

    @Test
    func overlappingIncompleteRootPreventsBroaderRootFromEvictingItsRecords() {
        let broad = scanRoot("/Volumes/Apps")
        let offlineNested = scanRoot("/Volumes/Apps/External")
        let retained = record("external", at: "/Volumes/Apps/External/Tool.app")
        let removed = record("removed", at: "/Volumes/Apps/Old.app")
        let visible = record("new", at: "/Volumes/Apps/New.app")
        let scan = ApplicationScanResult(
            records: [visible],
            roots: [outcome(broad, .complete), outcome(offlineNested, .unavailable)]
        )

        let result = CatalogScanMerger.reconcile(previous: [retained, removed], scan: scan)

        #expect(Set(result.reconciliation.records.map(\.id)) == ["external", "new"])
        #expect(result.reconciliation.removedIDs == ["removed"])
    }

    @Test
    func uniqueBundleMoveDuringPartialScanPreservesStableID() {
        let root = scanRoot("/Applications")
        let previous = ApplicationRecord(
            id: "stable", name: "Editor", bundleIdentifier: "example.editor",
            url: URL(fileURLWithPath: "/Applications/Old/Editor.app"))
        let moved = ApplicationRecord(
            id: "provisional", name: "Editor", bundleIdentifier: "example.editor",
            url: URL(fileURLWithPath: "/Applications/New/Editor.app"))
        let scan = ApplicationScanResult(
            records: [moved], roots: [outcome(root, .partial)])

        let result = CatalogScanMerger.reconcile(previous: [previous], scan: scan)

        #expect(result.reconciliation.records.map(\.id) == ["stable"])
        #expect(result.reconciliation.records.first?.url == moved.url)
        #expect(result.reconciliation.idRemappings == ["provisional": "stable"])
    }

    private func scanRoot(_ path: String) -> ApplicationScanRoot {
        ApplicationScanRoot(id: path, url: URL(fileURLWithPath: path), kind: .custom)
    }

    private func outcome(
        _ root: ApplicationScanRoot, _ completeness: ApplicationRootScanOutcome.Completeness
    ) -> ApplicationRootScanOutcome {
        ApplicationRootScanOutcome(root: root, completeness: completeness, issues: [])
    }

    private func record(_ id: String, at path: String) -> ApplicationRecord {
        ApplicationRecord(
            id: id,
            name: URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent,
            bundleIdentifier: "example.\(id)",
            url: URL(fileURLWithPath: path)
        )
    }
}
