import Foundation
import LauncherCore
import Testing

@testable import LauncherInfrastructure

struct PersistentDocumentStoreTests {
    @Test
    func saveAndLoadRoundTrip() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = fixture.store()
        let document = try PersistentDocument(
            organization: OrganizationSnapshot(favoriteIDs: ["favorite"])
        )

        try await store.save(document)

        #expect(try await store.load() == .loaded(document))
    }

    @Test
    func corruptPrimaryOffersPreviousGoodBackupWithoutChangingEitherFile() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = fixture.store()
        let first = try PersistentDocument()
        let second = try PersistentDocument(
            organization: OrganizationSnapshot(favoriteIDs: ["second"])
        )
        try await store.save(first)
        try await store.save(second)
        let corrupt = Data("truncated".utf8)
        try corrupt.write(to: fixture.documentURL)

        let result = try await store.load()

        #expect(result == .recoveryAvailable(backup: first, primaryIssue: .invalid(.malformed)))
        #expect(try Data(contentsOf: fixture.documentURL) == corrupt)
        #expect(try PersistentDocumentCodec.decode(Data(contentsOf: fixture.backupURL)) == first)
    }

    @Test
    func missingPrimaryOffersExistingBackupForExplicitRecovery() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let backup = try PersistentDocument(
            organization: OrganizationSnapshot(favoriteIDs: ["backup"])
        )
        try PersistentDocumentCodec.encode(backup).write(to: fixture.backupURL)

        let result = try await fixture.store().load()

        #expect(result == .recoveryAvailable(backup: backup, primaryIssue: .unreadable))
    }

    @Test
    func corruptPrimaryWithoutBackupThrowsAndSaveRefusesToOverwriteIt() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let corrupt = Data("broken".utf8)
        try corrupt.write(to: fixture.documentURL)
        let store = fixture.store()

        await #expect(throws: PersistentDocumentStoreError.invalidPrimary(.malformed)) {
            try await store.load()
        }
        await #expect(throws: PersistentDocumentStoreError.invalidPrimary(.malformed)) {
            try await store.save(PersistentDocument())
        }
        #expect(try Data(contentsOf: fixture.documentURL) == corrupt)
    }

    @Test
    func futureSchemaIsPreservedAndReported() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let valid = try PersistentDocumentCodec.encode(PersistentDocument())
        var object = try #require(JSONSerialization.jsonObject(with: valid) as? [String: Any])
        object["schemaVersion"] = 99
        let future = try JSONSerialization.data(withJSONObject: object)
        try future.write(to: fixture.documentURL)

        await #expect(
            throws: PersistentDocumentStoreError.invalidPrimary(
                .futureSchema(found: 99, supported: PersistentDocument.currentSchemaVersion)
            )
        ) {
            try await fixture.store().load()
        }
        #expect(try Data(contentsOf: fixture.documentURL) == future)
    }

    @Test
    func explicitImportArchivesInvalidPrimaryAndExportOmitsRecents() async throws {
        let date = Date(timeIntervalSince1970: 12)
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let corrupt = Data("preserve me".utf8)
        try corrupt.write(to: fixture.documentURL)
        let document = try PersistentDocument(
            organization: OrganizationSnapshot(
                favoriteIDs: ["favorite"],
                recents: [RecentApplication(applicationID: "recent", accessedAt: date)]
            )
        )
        let store = fixture.store(clock: { Date(timeIntervalSince1970: 42) })

        let exported = try await store.exportData(document)
        #expect(try PersistentDocumentCodec.decode(exported).organization.recents.isEmpty)
        let imported = try await store.importData(try PersistentDocumentCodec.encode(document))

        #expect(imported == document)
        #expect(try await store.load() == .loaded(document))
        let archive = fixture.root.appending(path: "state.preserved-42000.json")
        #expect(try Data(contentsOf: archive) == corrupt)
    }

    @Test
    func catalogCacheRoundTripsSeparatelyFromUserState() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = fixture.store()
        let catalog = ApplicationCatalog(
            records: [
                ApplicationRecord(
                    id: "app",
                    name: "App",
                    bundleIdentifier: "example.app",
                    url: URL(fileURLWithPath: "/Applications/App.app")
                )
            ],
            generation: 7
        )

        try await store.saveCatalog(catalog)

        #expect(try await store.loadCatalog() == catalog)
        #expect(try await store.load() == .notFound)
    }

    @Test
    func catalogCacheRejectsDuplicateIDs() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let duplicateRecords = [
            ApplicationRecord(
                id: "same", name: "One", bundleIdentifier: nil,
                url: URL(fileURLWithPath: "/Applications/One.app")
            ),
            ApplicationRecord(
                id: "same", name: "Two", bundleIdentifier: nil,
                url: URL(fileURLWithPath: "/Applications/Two.app")
            ),
        ]
        try JSONEncoder().encode(ApplicationCatalog(records: duplicateRecords)).write(
            to: fixture.catalogURL
        )

        await #expect(throws: PersistentDocumentStoreError.invalidCatalog) {
            try await fixture.store().loadCatalog()
        }
    }

    @Test(arguments: ["", "   "])
    func catalogCacheRejectsEmptyApplicationNames(_ name: String) async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let catalog = ApplicationCatalog(records: [
            ApplicationRecord(
                id: "app", name: name, bundleIdentifier: "example.app",
                url: URL(fileURLWithPath: "/Applications/App.app")
            )
        ])

        await #expect(throws: PersistentDocumentStoreError.invalidCatalog) {
            try await fixture.store().saveCatalog(catalog)
        }
    }

    @Test
    func catalogCacheRejectsNonFileURL() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let url = try #require(URL(string: "https://example.com/App.app"))
        let catalog = ApplicationCatalog(records: [
            ApplicationRecord(id: "app", name: "App", bundleIdentifier: nil, url: url)
        ])

        await #expect(throws: PersistentDocumentStoreError.invalidCatalog) {
            try await fixture.store().saveCatalog(catalog)
        }
    }

    @Test
    func catalogCacheRejectsMalformedBundleIdentifier() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let catalog = ApplicationCatalog(records: [
            ApplicationRecord(
                id: "app", name: "App", bundleIdentifier: " example.app ",
                url: URL(fileURLWithPath: "/Applications/App.app"))
        ])

        await #expect(throws: PersistentDocumentStoreError.invalidCatalog) {
            try await fixture.store().saveCatalog(catalog)
        }
    }

    @Test
    func oversizedImportIsRejectedBeforeDecoding() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let data = Data(count: PersistentDocumentStore.maximumDocumentBytes + 1)

        await #expect(
            throws: PersistentDocumentStoreError.importTooLarge(
                limit: PersistentDocumentStore.maximumDocumentBytes)
        ) {
            try await fixture.store().previewImport(data)
        }
    }

    @Test
    func oversizedStoredDocumentIsReportedWithoutReadingContents() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = PersistentDocumentStore(
            documentURL: fixture.documentURL,
            backupURL: fixture.backupURL,
            catalogURL: fixture.catalogURL,
            clock: Date.init,
            fileSystem: OversizedFileSystem()
        )

        await #expect(
            throws: PersistentDocumentStoreError.documentTooLarge(
                limit: PersistentDocumentStore.maximumDocumentBytes)
        ) {
            try await store.load()
        }
    }

    @Test
    func repeatedRecoveryArchivesDoNotOverwriteEarlierPreservedData() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = fixture.store(clock: { Date(timeIntervalSince1970: 42) })
        let imported = try PersistentDocument()
        try Data("first".utf8).write(to: fixture.documentURL)
        try await store.importData(PersistentDocumentCodec.encode(imported))
        try Data("second".utf8).write(to: fixture.documentURL)
        try await store.importData(PersistentDocumentCodec.encode(imported))

        #expect(
            try Data(contentsOf: fixture.root.appending(path: "state.preserved-42000.json"))
                == Data("first".utf8))
        #expect(
            try Data(contentsOf: fixture.root.appending(path: "state.preserved-42000-2.json"))
                == Data("second".utf8))
    }

    @Test
    func writeFailureIsObservable() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = PersistentDocumentStore(
            documentURL: fixture.documentURL,
            backupURL: fixture.backupURL,
            catalogURL: fixture.catalogURL,
            clock: Date.init,
            fileSystem: FailingWriteFileSystem()
        )

        await #expect(throws: PersistentDocumentStoreError.writeFailed) {
            try await store.save(PersistentDocument())
        }
    }
}

private final class StoreFixture {
    let root: URL
    let documentURL: URL
    let backupURL: URL
    let catalogURL: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        documentURL = root.appending(path: "state.json")
        backupURL = root.appending(path: "state.backup.json")
        catalogURL = root.appending(path: "catalog.json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func store(clock: @escaping @Sendable () -> Date = Date.init) -> PersistentDocumentStore {
        PersistentDocumentStore(
            documentURL: documentURL,
            backupURL: backupURL,
            catalogURL: catalogURL,
            clock: clock
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

private struct FailingWriteFileSystem: PersistentDocumentFileSystem {
    func exists(_: URL) -> Bool { false }
    func size(_: URL) throws -> Int { 0 }
    func read(_: URL, upToCount _: Int) throws -> Data { throw CocoaError(.fileReadUnknown) }
    func createDirectory(_: URL) throws {}
    func writeAtomic(_: Data, to _: URL) throws { throw CocoaError(.fileWriteUnknown) }
    func copy(_: URL, to _: URL) throws { throw CocoaError(.fileWriteUnknown) }
}

private struct OversizedFileSystem: PersistentDocumentFileSystem {
    func exists(_: URL) -> Bool { true }
    func size(_: URL) throws -> Int { PersistentDocumentStore.maximumDocumentBytes + 1 }
    func read(_: URL, upToCount _: Int) throws -> Data {
        Issue.record("Oversized file contents should not be read")
        return Data()
    }
    func createDirectory(_: URL) throws {}
    func writeAtomic(_: Data, to _: URL) throws {}
    func copy(_: URL, to _: URL) throws {}
}
