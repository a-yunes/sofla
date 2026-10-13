import Foundation

protocol PersistentDocumentFileSystem: Sendable {
    func exists(_ url: URL) -> Bool
    func size(_ url: URL) throws -> Int
    func read(_ url: URL, upToCount count: Int) throws -> Data
    func createDirectory(_ url: URL) throws
    func writeAtomic(_ data: Data, to url: URL) throws
    func copy(_ source: URL, to destination: URL) throws
}

enum PersistentDocumentFileError: Error {
    case tooLarge
}

struct FoundationDocumentFileSystem: PersistentDocumentFileSystem {
    func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    func read(_ url: URL, upToCount count: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        return try handle.read(upToCount: count) ?? Data()
    }

    func size(_ url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = attributes[.size] as? NSNumber else {
            throw CocoaError(.fileReadUnknown)
        }
        return size.intValue
    }

    func createDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func writeAtomic(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }

    func copy(_ source: URL, to destination: URL) throws {
        try FileManager.default.copyItem(at: source, to: destination)
    }
}
