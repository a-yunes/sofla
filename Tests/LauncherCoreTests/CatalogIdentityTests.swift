import Foundation
import Testing

@testable import LauncherCore

struct CatalogIdentityTests {
    @Test(arguments: [false, true])
    func reusingAMovedApplicationsPathKeepsDistinctStableIdentities(reverse: Bool) throws {
        let original = record("/Applications/A.app", bundle: "example.original")
        let moved = record("/Applications/B.app", bundle: "example.original")
        let replacement = record("/Applications/A.app", bundle: "example.replacement")
        let companion = record("/Applications/C.app", bundle: "example.companion")
        var library = try LibraryState(records: [original, companion])
        try library.apply(.setFavorite(applicationID: original.id, isFavorite: true))
        try library.apply(.setAliases(applicationID: original.id, values: ["my editor"]))
        try library.apply(
            .createFolder(
                id: "folder", name: "Work", applicationIDs: [original.id, companion.id],
                destination: 0))
        _ = try library.reconcileCatalog([moved, companion])
        let organization = library.organization
        let discoveries =
            reverse ? [replacement, companion, moved] : [moved, companion, replacement]

        _ = try library.reconcileCatalog(discoveries)

        let newID = try #require(library.records.first { $0.url == replacement.url }?.id)
        #expect(newID != original.id)
        #expect(library.records.first { $0.url == moved.url }?.id == original.id)
        #expect(Set(library.records.map(\.id)).count == 3)
        #expect(library.favoriteIDs == organization.favoriteIDs)
        #expect(library.folders == organization.folders)
        #expect(library.aliases == organization.aliases)
        let after = library
        _ = try library.reconcileCatalog(discoveries.reversed())
        #expect(library.records.first { $0.url == replacement.url }?.id == newID)
        #expect(library.organization == after.organization)
    }

    @Test
    func rejectedDiscoveryPreservesEntireLibrary() throws {
        let original = record("/Applications/A.app", bundle: "example.original")
        var library = try LibraryState(records: [original])
        try library.apply(.setFavorite(applicationID: original.id, isFavorite: true))
        let before = library
        #expect(throws: LibraryError.duplicateRecordID) {
            try library.reconcileCatalog([original, original])
        }
        #expect(library == before)
        var malformed = record("/Applications/B.app", bundle: "example.malformed")
        malformed.name = ""
        #expect(throws: ApplicationRecord.ValidationError.invalidName) {
            try library.reconcileCatalog([malformed])
        }
        #expect(library == before)
    }

    @Test
    func reusedPathCannotClaimRetiredMovedIdentity() throws {
        let original = record("/Applications/A.app", bundle: "example.original")
        let moved = record("/Applications/B.app", bundle: "example.original")
        var library = try LibraryState(records: [original])
        try library.apply(.setFavorite(applicationID: original.id, isFavorite: true))
        _ = try library.reconcileCatalog([moved])
        _ = try library.reconcileCatalog([])
        let replacement = record("/Applications/A.app", bundle: "example.replacement")

        _ = try library.reconcileCatalog([replacement])

        #expect(library.records.first?.id != original.id)
        #expect(library.favoriteIDs == [original.id])
        #expect(library.retiredApplicationReferences.map(\.id) == [original.id])
    }

    private func record(_ path: String, bundle: String) -> ApplicationRecord {
        let url = URL(fileURLWithPath: path)
        return ApplicationRecord(
            id: "url:\(url.absoluteString)", name: bundle, bundleIdentifier: bundle, url: url)
    }
}
