import Foundation
import LauncherCore

public enum StoredDocumentIssue: Error, Equatable, Sendable {
    case unreadable
    case invalid(PersistentDocumentError)
    case tooLarge(limit: Int)
}

public enum PersistentDocumentLoadResult: Equatable, Sendable {
    case notFound
    case loaded(PersistentDocument)
    case recoveryAvailable(backup: PersistentDocument, primaryIssue: StoredDocumentIssue)
}

public enum PersistentDocumentStoreError: Error, Equatable, Sendable {
    case unreadablePrimary
    case invalidPrimary(PersistentDocumentError)
    case unavailableBackup
    case invalidBackup(PersistentDocumentError)
    case writeFailed
    case archiveFailed
    case invalidCatalog
    case documentTooLarge(limit: Int)
    case importTooLarge(limit: Int)
    case catalogTooLarge(limit: Int)
}

public actor PersistentDocumentStore {
    public static let maximumDocumentBytes = 10 * 1_024 * 1_024
    public static let maximumCatalogBytes = 20 * 1_024 * 1_024

    private let documentURL: URL
    private let backupURL: URL
    private let catalogURL: URL
    private let clock: @Sendable () -> Date
    private let fileSystem: any PersistentDocumentFileSystem

    public init(
        documentURL: URL,
        backupURL: URL,
        catalogURL: URL,
        clock: @escaping @Sendable () -> Date = Date.init
    ) {
        self.init(
            documentURL: documentURL,
            backupURL: backupURL,
            catalogURL: catalogURL,
            clock: clock,
            fileSystem: FoundationDocumentFileSystem()
        )
    }

    init(
        documentURL: URL,
        backupURL: URL,
        catalogURL: URL,
        clock: @escaping @Sendable () -> Date,
        fileSystem: any PersistentDocumentFileSystem
    ) {
        self.documentURL = documentURL
        self.backupURL = backupURL
        self.catalogURL = catalogURL
        self.clock = clock
        self.fileSystem = fileSystem
    }

    public func load() throws -> PersistentDocumentLoadResult {
        guard fileSystem.exists(documentURL) else {
            guard fileSystem.exists(backupURL) else { return .notFound }
            switch readDocument(at: backupURL) {
            case .success(let backup):
                return .recoveryAvailable(backup: backup, primaryIssue: .unreadable)
            case .failure(.unreadable): throw PersistentDocumentStoreError.unavailableBackup
            case .failure(.invalid(let error)):
                throw PersistentDocumentStoreError.invalidBackup(error)
            case .failure(.tooLarge):
                throw PersistentDocumentStoreError.documentTooLarge(
                    limit: Self.maximumDocumentBytes)
            }
        }

        let primary: Result<PersistentDocument, StoredDocumentIssue> = readDocument(at: documentURL)
        switch primary {
        case .success(let document): return .loaded(document)
        case .failure(let primaryIssue):
            guard fileSystem.exists(backupURL) else {
                switch primaryIssue {
                case .unreadable: throw PersistentDocumentStoreError.unreadablePrimary
                case .invalid(let error): throw PersistentDocumentStoreError.invalidPrimary(error)
                case .tooLarge:
                    throw PersistentDocumentStoreError.documentTooLarge(
                        limit: Self.maximumDocumentBytes)
                }
            }
            switch readDocument(at: backupURL) {
            case .success(let backup):
                return .recoveryAvailable(backup: backup, primaryIssue: primaryIssue)
            case .failure(.unreadable): throw PersistentDocumentStoreError.unavailableBackup
            case .failure(.invalid(let error)):
                throw PersistentDocumentStoreError.invalidBackup(error)
            case .failure(.tooLarge):
                throw PersistentDocumentStoreError.documentTooLarge(
                    limit: Self.maximumDocumentBytes)
            }
        }
    }

    public func save(_ document: PersistentDocument) throws {
        let encoded = try PersistentDocumentCodec.encode(document)
        guard encoded.count <= Self.maximumDocumentBytes else {
            throw PersistentDocumentStoreError.documentTooLarge(limit: Self.maximumDocumentBytes)
        }
        if fileSystem.exists(documentURL) {
            switch readDocument(at: documentURL) {
            case .success:
                do {
                    try fileSystem.createDirectory(backupURL.deletingLastPathComponent())
                    try fileSystem.writeAtomic(
                        try boundedRead(documentURL, maximumBytes: Self.maximumDocumentBytes),
                        to: backupURL)
                } catch {
                    throw PersistentDocumentStoreError.writeFailed
                }
            case .failure(.unreadable): throw PersistentDocumentStoreError.unreadablePrimary
            case .failure(.invalid(let error)):
                throw PersistentDocumentStoreError.invalidPrimary(error)
            case .failure(.tooLarge):
                throw PersistentDocumentStoreError.documentTooLarge(
                    limit: Self.maximumDocumentBytes)
            }
        }
        try write(encoded, to: documentURL)
    }

    public func restoreBackup() throws -> PersistentDocument {
        guard fileSystem.exists(backupURL) else {
            throw PersistentDocumentStoreError.unavailableBackup
        }
        let backupData: Data
        let backup: PersistentDocument
        do {
            backupData = try boundedRead(backupURL, maximumBytes: Self.maximumDocumentBytes)
            backup = try PersistentDocumentCodec.decode(backupData)
        } catch PersistentDocumentFileError.tooLarge {
            throw PersistentDocumentStoreError.documentTooLarge(
                limit: Self.maximumDocumentBytes)
        } catch let error as PersistentDocumentError {
            throw PersistentDocumentStoreError.invalidBackup(error)
        } catch {
            throw PersistentDocumentStoreError.unavailableBackup
        }
        try archivePrimaryIfPresent()
        try write(backupData, to: documentURL)
        return backup
    }

    public func exportData(_ document: PersistentDocument) throws -> Data {
        let data = try PersistentDocumentCodec.encodeForExport(document)
        guard data.count <= Self.maximumDocumentBytes else {
            throw PersistentDocumentStoreError.documentTooLarge(limit: Self.maximumDocumentBytes)
        }
        return data
    }

    public func previewImport(_ data: Data) throws -> PersistentDocument {
        guard data.count <= Self.maximumDocumentBytes else {
            throw PersistentDocumentStoreError.importTooLarge(limit: Self.maximumDocumentBytes)
        }
        return try PersistentDocumentCodec.decode(data)
    }

    @discardableResult
    public func importData(_ data: Data) throws -> PersistentDocument {
        let document = try previewImport(data)
        if fileSystem.exists(documentURL) {
            switch readDocument(at: documentURL) {
            case .success:
                do {
                    try fileSystem.createDirectory(backupURL.deletingLastPathComponent())
                    try fileSystem.writeAtomic(
                        try boundedRead(documentURL, maximumBytes: Self.maximumDocumentBytes),
                        to: backupURL)
                } catch {
                    throw PersistentDocumentStoreError.writeFailed
                }
            case .failure:
                try archivePrimaryIfPresent()
            }
        }
        try write(try PersistentDocumentCodec.encode(document), to: documentURL)
        return document
    }

    public func loadCatalog() throws -> ApplicationCatalog? {
        guard fileSystem.exists(catalogURL) else { return nil }
        do {
            let catalog = try JSONDecoder().decode(
                ApplicationCatalog.self,
                from: boundedRead(catalogURL, maximumBytes: Self.maximumCatalogBytes)
            )
            try CatalogCacheValidator.validate(catalog)
            return catalog
        } catch PersistentDocumentFileError.tooLarge {
            throw PersistentDocumentStoreError.catalogTooLarge(limit: Self.maximumCatalogBytes)
        } catch let error as PersistentDocumentStoreError {
            throw error
        } catch is DecodingError {
            throw PersistentDocumentStoreError.invalidCatalog
        } catch {
            throw StoredDocumentIssue.unreadable
        }
    }

    public func saveCatalog(_ catalog: ApplicationCatalog) throws {
        do {
            try CatalogCacheValidator.validate(catalog)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(catalog)
            guard data.count <= Self.maximumCatalogBytes else {
                throw PersistentDocumentStoreError.catalogTooLarge(
                    limit: Self.maximumCatalogBytes)
            }
            try write(data, to: catalogURL)
        } catch let error as PersistentDocumentStoreError {
            throw error
        } catch {
            throw PersistentDocumentStoreError.writeFailed
        }
    }

    private func readDocument(at url: URL) -> Result<PersistentDocument, StoredDocumentIssue> {
        do {
            return .success(
                try PersistentDocumentCodec.decode(
                    boundedRead(url, maximumBytes: Self.maximumDocumentBytes)))
        } catch PersistentDocumentFileError.tooLarge {
            return .failure(.tooLarge(limit: Self.maximumDocumentBytes))
        } catch let error as PersistentDocumentError {
            return .failure(.invalid(error))
        } catch {
            return .failure(.unreadable)
        }
    }

    private func write(_ data: Data, to url: URL) throws {
        do {
            try fileSystem.createDirectory(url.deletingLastPathComponent())
            try fileSystem.writeAtomic(data, to: url)
        } catch {
            throw PersistentDocumentStoreError.writeFailed
        }
    }

    private func boundedRead(_ url: URL, maximumBytes: Int) throws -> Data {
        guard try fileSystem.size(url) <= maximumBytes else {
            throw PersistentDocumentFileError.tooLarge
        }
        let data = try fileSystem.read(url, upToCount: maximumBytes + 1)
        guard data.count <= maximumBytes else { throw PersistentDocumentFileError.tooLarge }
        return data
    }

    private func archivePrimaryIfPresent() throws {
        guard fileSystem.exists(documentURL) else { return }
        let milliseconds = Int64(clock().timeIntervalSince1970 * 1_000)
        let archiveBaseURL =
            documentURL
            .deletingPathExtension()
            .appendingPathExtension("preserved-\(milliseconds).json")
        var archiveURL = archiveBaseURL
        var suffix = 2
        while fileSystem.exists(archiveURL) {
            archiveURL =
                documentURL
                .deletingPathExtension()
                .appendingPathExtension("preserved-\(milliseconds)-\(suffix).json")
            suffix += 1
        }
        do {
            try fileSystem.copy(documentURL, to: archiveURL)
        } catch {
            throw PersistentDocumentStoreError.archiveFailed
        }
    }
}
