import Foundation
import Testing

@testable import LauncherCore

struct CatalogReconciliationTests {
    @Test
    func uniqueBundleMovePreservesStableIdentityAndMetadata() {
        let old = app("stable", "Old", "com.example.app", "/Applications/Old.app")
        let moved = app("scan-new", "Updated", "com.example.app", "/Applications/New.app")
        let result = CatalogReconciler.reconcile(previous: [old], discovered: [moved])

        #expect(
            result.records == [app("stable", "Updated", "com.example.app", "/Applications/New.app")]
        )
        #expect(result.idRemappings == ["scan-new": "stable"])
        #expect(result.removedIDs.isEmpty)
    }

    @Test
    func duplicateBundleInstallsRemainDistinctAndExactPathsWin() {
        let first = app("one", "App", "same.bundle", "/Applications/App.app")
        let second = app("two", "App Beta", "same.bundle", "/Volumes/Beta/App.app")
        let scan = [
            app("new-two", "Beta 2", "same.bundle", "/Volumes/Beta/App.app"),
            app("new-three", "Third", "same.bundle", "/synthetic/user/Applications/App.app"),
        ]
        let result = CatalogReconciler.reconcile(previous: [first, second], discovered: scan)
        #expect(result.records.map(\.id) == ["two", "new-three"])
        #expect(result.removedIDs == ["one"])
    }

    @Test
    func removalIsReportedWithoutMutatingRemainingOrder() {
        let records = [app("a", "A", nil, "/A.app"), app("b", "B", nil, "/B.app")]
        let result = CatalogReconciler.reconcile(previous: records, discovered: [records[1]])
        #expect(result.records == [records[1]])
        #expect(result.removedIDs == ["a"])
    }

}

private func app(_ id: String, _ name: String, _ bundle: String?, _ path: String)
    -> ApplicationRecord
{
    ApplicationRecord(id: id, name: name, bundleIdentifier: bundle, url: URL(fileURLWithPath: path))
}
