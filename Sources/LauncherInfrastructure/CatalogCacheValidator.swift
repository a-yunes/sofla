import Foundation
import LauncherCore

enum CatalogCacheValidator {
    static let maximumRecords = 20_000
    static let maximumNameLength = 512
    static let maximumIdentifierLength = 4_096
    static let maximumBundleIdentifierLength = 1_024

    static func validate(_ catalog: ApplicationCatalog) throws {
        guard catalog.records.count <= maximumRecords else { throw invalid }

        let ids = catalog.records.map(\.id)
        guard ids.allSatisfy({ !$0.isEmpty && $0.count <= maximumIdentifierLength }),
            Set(ids).count == ids.count
        else { throw invalid }

        let canonicalURLs = catalog.records.map { $0.url.standardizedFileURL }
        guard Set(canonicalURLs).count == canonicalURLs.count else { throw invalid }

        let recordURLs = Set(canonicalURLs.map(\.path))
        guard Set(catalog.discoveryRootsByPath.keys).isSubset(of: recordURLs),
            catalog.discoveryRootsByPath.values.allSatisfy({ roots in
                !roots.isEmpty && roots.allSatisfy { $0.hasPrefix("/") }
            })
        else { throw invalid }

        for record in catalog.records {
            try validate(record)
        }
    }

    static func validate(_ record: ApplicationRecord) throws {
        guard !record.id.isEmpty, record.id.count <= maximumIdentifierLength else {
            throw invalid
        }
        let name = record.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= maximumNameLength else { throw invalid }
        guard record.url.isFileURL, record.url.pathExtension.lowercased() == "app" else {
            throw invalid
        }
        if let bundleIdentifier = record.bundleIdentifier {
            guard !bundleIdentifier.isEmpty,
                bundleIdentifier
                    == bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines),
                bundleIdentifier.count <= maximumBundleIdentifierLength
            else { throw invalid }
        }
    }

    private static var invalid: PersistentDocumentStoreError { .invalidCatalog }
}
