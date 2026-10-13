import Foundation
import LauncherCore
import Synchronization
import Testing

@testable import LauncherInfrastructure

struct PersistentRecoveryTests {
    private let primary = URL(fileURLWithPath: "/fixture/library.json")
    private let backup = URL(fileURLWithPath: "/fixture/library.backup.json")

    @Test
    func restoreArchivesOriginalAndKeepsUsableBackup() async throws {
        let document = try PersistentDocument()
        let data = try PersistentDocumentCodec.encode(document)
        let original = Data("invalid original".utf8)
        let files = MemoryDocumentFileSystem(files: [primary: original, backup: data])
        let store = makeStore(files)

        #expect(try await store.restoreBackup() == document)

        #expect(files.contents(primary) == data)
        #expect(files.contents(backup) == data)
        #expect(files.contents(archive) == original)
        #expect(try await store.load() == .loaded(document))
    }

    @Test(arguments: [MemoryDocumentFileSystem.Failure.copy, .writePrimary])
    func failedRestorePreservesPrimaryAndBackup(failure: MemoryDocumentFileSystem.Failure)
        async throws
    {
        let document = try PersistentDocument()
        let data = try PersistentDocumentCodec.encode(document)
        let original = Data("invalid original".utf8)
        let files = MemoryDocumentFileSystem(
            files: [primary: original, backup: data], failure: failure)
        let store = makeStore(files)

        await #expect(
            throws: failure == .copy
                ? PersistentDocumentStoreError.archiveFailed : .writeFailed
        ) {
            try await store.restoreBackup()
        }

        #expect(files.contents(primary) == original)
        #expect(files.contents(backup) == data)
        #expect(files.contents(archive) == (failure == .copy ? nil : original))
        guard case .recoveryAvailable(let recovered, _) = try await store.load() else {
            Issue.record("Failed restore must still offer the usable backup")
            return
        }
        #expect(recovered == document)
    }

    @Test(arguments: [MemoryDocumentFileSystem.Failure.writeBackup, .writePrimary])
    func failedSaveLeavesLastGoodPrimaryLoadable(failure: MemoryDocumentFileSystem.Failure)
        async throws
    {
        let old = try PersistentDocument()
        var preferences = LauncherPreferences()
        preferences.showsKeyboardHints.toggle()
        let next = try PersistentDocument(preferences: preferences)
        let data = try PersistentDocumentCodec.encode(old)
        let previousBackup = Data("older backup".utf8)
        let files = MemoryDocumentFileSystem(
            files: [primary: data, backup: previousBackup], failure: failure)
        let store = makeStore(files)

        await #expect(throws: PersistentDocumentStoreError.writeFailed) {
            try await store.save(next)
        }

        #expect(files.contents(primary) == data)
        #expect(files.contents(backup) == (failure == .writeBackup ? previousBackup : data))
        #expect(try await store.load() == .loaded(old))
    }

    @Test(arguments: [false, true])
    func missingOrInvalidBackupNeverTouchesPrimary(missing: Bool) async throws {
        let original = Data("original".utf8)
        var bytes = [primary: original]
        if !missing { bytes[backup] = Data("bad backup".utf8) }
        let files = MemoryDocumentFileSystem(files: bytes)
        let store = makeStore(files)

        await #expect(throws: (any Error).self) { try await store.restoreBackup() }

        #expect(files.snapshot == bytes)
    }

    private var archive: URL { URL(fileURLWithPath: "/fixture/library.preserved-42000.json") }

    private func makeStore(_ files: MemoryDocumentFileSystem) -> PersistentDocumentStore {
        PersistentDocumentStore(
            documentURL: primary, backupURL: backup,
            catalogURL: URL(fileURLWithPath: "/fixture/catalog.json"),
            clock: { Date(timeIntervalSince1970: 42) }, fileSystem: files)
    }
}

final class MemoryDocumentFileSystem: PersistentDocumentFileSystem {
    enum Failure: Sendable { case copy, writePrimary, writeBackup }
    private let files: Mutex<[URL: Data]>
    private let failure: Failure?

    init(files: [URL: Data], failure: Failure? = nil) {
        self.files = Mutex(files)
        self.failure = failure
    }

    var snapshot: [URL: Data] { files.withLock { $0 } }
    func contents(_ url: URL) -> Data? { files.withLock { $0[url] } }
    func exists(_ url: URL) -> Bool { contents(url) != nil }
    func size(_ url: URL) throws -> Int { try read(url, upToCount: .max).count }
    func read(_ url: URL, upToCount count: Int) throws -> Data {
        guard let data = contents(url) else { throw CocoaError(.fileReadNoSuchFile) }
        return data.prefix(count)
    }
    func createDirectory(_ url: URL) throws {}
    func writeAtomic(_ data: Data, to url: URL) throws {
        if (failure == .writePrimary && url.lastPathComponent == "library.json")
            || (failure == .writeBackup && url.lastPathComponent == "library.backup.json")
        {
            throw CocoaError(.fileWriteUnknown)
        }
        files.withLock { $0[url] = data }
    }
    func copy(_ source: URL, to destination: URL) throws {
        if failure == .copy { throw CocoaError(.fileWriteUnknown) }
        let data = try read(source, upToCount: .max)
        files.withLock { $0[destination] = data }
    }
}
