import Foundation
import Testing

@testable import LauncherCore

struct PersistentDocumentTests {
    @Test
    func roundTripIsDeterministicAndExportOmitsHistory() throws {
        let folder = try ApplicationFolder(id: "f", name: "Folder", applicationIDs: ["a"])
        let organization = OrganizationSnapshot(
            rootOrder: [.folder("f")], folders: [folder], favoriteIDs: ["a"],
            aliases: ["a": ["Mail"]],
            recents: [
                RecentApplication(applicationID: "a", accessedAt: Date(timeIntervalSince1970: 1))
            ]
        )
        let document = try PersistentDocument(organization: organization)
        let data = try PersistentDocumentCodec.encode(document)
        #expect(try PersistentDocumentCodec.decode(data) == document)
        #expect(try PersistentDocumentCodec.encode(document) == data)
        #expect(
            try PersistentDocumentCodec.decode(PersistentDocumentCodec.encodeForExport(document))
                .organization.recents.isEmpty)
    }

    @Test
    func organizationOrderingModeIsPersistedWithoutCompatibilityFallback() throws {
        let document = try PersistentDocument(
            organization: OrganizationSnapshot(
                rootOrder: [.application("a")], orderingMode: .manual))
        let data = try PersistentDocumentCodec.encode(document)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let organization = try #require(object["organization"] as? [String: Any])
        #expect(organization["orderingMode"] as? String == "manual")
        #expect(try PersistentDocumentCodec.decode(data).organization.orderingMode == .manual)

        var missing = object
        var missingOrganization = try #require(missing["organization"] as? [String: Any])
        missingOrganization.removeValue(forKey: "orderingMode")
        missing["organization"] = missingOrganization
        let missingData = try JSONSerialization.data(withJSONObject: missing)
        #expect(throws: PersistentDocumentError.malformed) {
            try PersistentDocumentCodec.decode(missingData)
        }
    }

    @Test
    func malformedFutureAndInvalidSchemaAreDistinct() throws {
        #expect(throws: PersistentDocumentError.malformed) {
            try PersistentDocumentCodec.decode(Data("{".utf8))
        }
        let document = try PersistentDocument()
        var object = try #require(
            JSONSerialization.jsonObject(with: PersistentDocumentCodec.encode(document))
                as? [String: Any])
        object["schemaVersion"] = 999
        let future = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: PersistentDocumentError.futureSchema(found: 999, supported: 1)) {
            try PersistentDocumentCodec.decode(future)
        }
        object["schemaVersion"] = 0
        let invalid = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: PersistentDocumentError.invalidSchemaVersion(0)) {
            try PersistentDocumentCodec.decode(invalid)
        }
    }

    @Test
    func duplicatePlacementAndMissingCatalogReferenceAreDetected() throws {
        let organization = OrganizationSnapshot(rootOrder: [.application("a"), .application("a")])
        #expect(throws: PersistentDocumentError.invalidOrganization(.duplicatePlacement)) {
            try PersistentDocument(organization: organization)
        }

        let valid = try PersistentDocument(
            organization: OrganizationSnapshot(rootOrder: [.application("missing")]))
        #expect(throws: LibraryError.unknownApplicationReference) {
            let state = try valid.libraryState(records: [])
            try state.validate(allowMissingApplicationReferences: false)
        }
    }

    @Test
    func mutatedPreferencesAreRejectedBeforeEncoding() throws {
        var preferences = LauncherPreferences()
        preferences.retentionDays = 0
        var document = try PersistentDocument()
        document.preferences = preferences
        #expect(throws: PersistentDocumentError.invalidPreferences) {
            try PersistentDocumentCodec.encode(document)
        }
    }

    @Test
    func malformedFolderAndOversizedHistoryAreRejected() throws {
        let invalidFolder = Data(#"{"id":"f","name":" ","applicationIDs":[]}"#.utf8)
        #expect(throws: LibraryError.emptyFolderName) {
            try JSONDecoder().decode(ApplicationFolder.self, from: invalidFolder)
        }

        let history = (0...RecentsPolicy.maximumHistoryLimit).map {
            RecentApplication(
                applicationID: "app-\($0)", accessedAt: Date(timeIntervalSince1970: 1))
        }
        #expect(
            throws: PersistentDocumentError.invalidOrganization(.recentHistoryLimitExceeded)
        ) {
            try PersistentDocument(organization: OrganizationSnapshot(recents: history))
        }
    }

    @Test
    func applicationReferencesPreservePortableIdentityAcrossUniqueMove() throws {
        let saved = ApplicationRecord(
            id: "stable", name: "Example", bundleIdentifier: "com.example.app",
            url: URL(fileURLWithPath: "/Applications/Example.app"))
        let document = try PersistentDocument(
            organization: OrganizationSnapshot(
                rootOrder: [.application("stable")], favoriteIDs: ["stable"]),
            applicationReferences: [saved]
        )
        let local = ApplicationRecord(
            id: "local-path-id", name: "Example Updated", bundleIdentifier: "com.example.app",
            url: URL(fileURLWithPath: "/synthetic/user/Applications/Example.app"))
        let state = try document.libraryState(records: [local])
        #expect(state.records.map(\.id) == ["stable"])
        #expect(state.records.first?.url == local.url)
        #expect(state.favoriteIDs == ["stable"])
        #expect(state.rootOrder == [.application("stable")])
    }

    @Test
    func ambiguousDuplicateReferencesDoNotMergeAndReferencesAreRequired() throws {
        let references = [
            ApplicationRecord(
                id: "old-a", name: "App", bundleIdentifier: "same.bundle",
                url: URL(fileURLWithPath: "/Applications/App.app")),
            ApplicationRecord(
                id: "old-b", name: "App Beta", bundleIdentifier: "same.bundle",
                url: URL(fileURLWithPath: "/Volumes/Beta/App.app")),
        ]
        let document = try PersistentDocument(
            organization: OrganizationSnapshot(
                rootOrder: [.application("old-a"), .application("old-b")],
                orderingMode: .manual),
            applicationReferences: references
        )
        let local = [
            ApplicationRecord(
                id: "new-a", name: "App", bundleIdentifier: "same.bundle",
                url: URL(fileURLWithPath: "/synthetic/user/Applications/App.app")),
            ApplicationRecord(
                id: "new-b", name: "App Beta", bundleIdentifier: "same.bundle",
                url: URL(fileURLWithPath: "/Volumes/New/App.app")),
        ]
        let state = try document.libraryState(records: local)
        #expect(state.records.map(\.id) == ["new-a", "new-b"])
        #expect(
            state.rootOrder == [
                .application("old-a"), .application("old-b"), .application("new-a"),
                .application("new-b"),
            ])

        var legacyObject = try #require(
            JSONSerialization.jsonObject(with: PersistentDocumentCodec.encode(document))
                as? [String: Any])
        legacyObject.removeValue(forKey: "applicationReferences")
        let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
        #expect(throws: PersistentDocumentError.malformed) {
            try PersistentDocumentCodec.decode(legacyData)
        }
    }

    @Test
    func applicationReferenceMetadataIsValidated() {
        let invalid = ApplicationRecord(
            id: "app", name: "App", bundleIdentifier: " bad.bundle ",
            url: URL(fileURLWithPath: "/Applications/App.app"))
        #expect(throws: PersistentDocumentError.invalidApplicationReferences) {
            try PersistentDocument(applicationReferences: [invalid])
        }
    }

    @Test
    func absentImportedReferenceCanReconcileWhenApplicationAppearsLater() throws {
        let exported = ApplicationRecord(
            id: "export-id", name: "Travel App", bundleIdentifier: "com.example.travel",
            url: URL(fileURLWithPath: "/Applications/Travel App.app"))
        let document = try PersistentDocument(
            organization: OrganizationSnapshot(
                rootOrder: [.application("export-id")], favoriteIDs: ["export-id"]),
            applicationReferences: [exported])
        let localOther = ApplicationRecord(
            id: "other", name: "Other", bundleIdentifier: "com.example.other",
            url: URL(fileURLWithPath: "/Applications/Other.app"))
        var state = try document.libraryState(records: [localOther])
        #expect(state.records.map(\.id) == ["other"])
        #expect(state.retiredApplicationReferences.map(\.id) == ["export-id"])

        let appeared = ApplicationRecord(
            id: "new-local-id", name: "Travel App", bundleIdentifier: "com.example.travel",
            url: URL(fileURLWithPath: "/synthetic/user/Applications/Travel App.app"))
        _ = try state.reconcileCatalog([localOther, appeared])
        #expect(state.records.map(\.id) == ["other", "export-id"])
        #expect(state.favoriteIDs == ["export-id"])
        #expect(state.retiredApplicationReferences.isEmpty)
    }
}
