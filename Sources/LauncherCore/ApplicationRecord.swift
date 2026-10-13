import Foundation

public struct ApplicationRecord: Codable, Equatable, Sendable, Identifiable {
    public static let maximumNameLength = 512
    public static let maximumIdentifierLength = 4_096
    public static let maximumBundleIdentifierLength = 1_024

    public let id: String
    public var name: String
    public var bundleIdentifier: String?
    public var url: URL

    public init(id: String, name: String, bundleIdentifier: String?, url: URL) {
        self.id = id
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.url = url
    }

    public func validate() throws {
        guard !id.isEmpty, id.count <= Self.maximumIdentifierLength else {
            throw ValidationError.invalidIdentifier
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, trimmedName.count <= Self.maximumNameLength else {
            throw ValidationError.invalidName
        }
        guard url.isFileURL, url.pathExtension.lowercased() == "app" else {
            throw ValidationError.invalidURL
        }
        if let bundleIdentifier {
            guard !bundleIdentifier.isEmpty,
                bundleIdentifier
                    == bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines),
                bundleIdentifier.count <= Self.maximumBundleIdentifierLength
            else { throw ValidationError.invalidBundleIdentifier }
        }
    }

    public enum ValidationError: Error, Equatable, Sendable {
        case invalidIdentifier
        case invalidName
        case invalidURL
        case invalidBundleIdentifier
    }
}

public struct ApplicationCatalog: Codable, Equatable, Sendable {
    public var records: [ApplicationRecord]
    public var generation: UInt64
    /// Canonical application paths mapped to the configured root paths that discovered them.
    public var discoveryRootsByPath: [String: Set<String>]

    public init(
        records: [ApplicationRecord] = [], generation: UInt64 = 0,
        discoveryRootsByPath: [String: Set<String>] = [:]
    ) {
        self.records = records
        self.generation = generation
        self.discoveryRootsByPath = discoveryRootsByPath
    }
}

public struct CatalogReconciliation: Equatable, Sendable {
    public let records: [ApplicationRecord]
    public let removedIDs: Set<String>
    public let idRemappings: [String: String]

    public init(
        records: [ApplicationRecord], removedIDs: Set<String>, idRemappings: [String: String]
    ) {
        self.records = records
        self.removedIDs = removedIDs
        self.idRemappings = idRemappings
    }
}

public enum CatalogReconciler {
    public static func reconcile(
        previous: [ApplicationRecord], discovered: [ApplicationRecord]
    ) -> CatalogReconciliation {
        let previousByURL = Dictionary(grouping: previous, by: canonicalURL)
        let previousByBundle = Dictionary(
            grouping: previous.compactMap { record in
                record.bundleIdentifier.map { ($0, record) }
            }, by: \.0)
        let discoveredByBundle = Dictionary(
            grouping: discovered.compactMap { record in
                record.bundleIdentifier.map { ($0, record) }
            }, by: \.0)

        var claimedPreviousIDs = Set<String>()
        var matches: [Int: ApplicationRecord] = [:]
        // Reserve exact paths before matching moves, independent of discovery order.
        for (index, candidate) in discovered.enumerated() {
            if let exact = previousByURL[canonicalURL(candidate)]?.first(where: {
                !claimedPreviousIDs.contains($0.id)
            }) {
                matches[index] = exact
                claimedPreviousIDs.insert(exact.id)
            }
        }
        for (index, candidate) in discovered.enumerated() where matches[index] == nil {
            if let bundleID = candidate.bundleIdentifier,
                previousByBundle[bundleID]?.count == 1,
                discoveredByBundle[bundleID]?.count == 1,
                let old = previousByBundle[bundleID]?.first?.1,
                claimedPreviousIDs.insert(old.id).inserted
            {
                matches[index] = old
            }
        }

        let previousIDs = Set(previous.map(\.id))
        var reservedIDs = previousIDs.union(discovered.map(\.id))
        var remappings: [String: String] = [:]
        var reconciled: [ApplicationRecord] = []
        for (index, candidate) in discovered.enumerated() {
            let id: String
            if let matched = matches[index] {
                id = matched.id
            } else if previousIDs.contains(candidate.id) {
                // A path-derived provisional ID may still belong to an app that moved away.
                // Reserve retired IDs too, so organization is never transferred to a new app.
                var suffix = 1
                var available: String
                repeat {
                    let ending = "#\(suffix)"
                    available =
                        String(
                            candidate.id.prefix(
                                ApplicationRecord.maximumIdentifierLength - ending.count)) + ending
                    suffix += 1
                } while !reservedIDs.insert(available).inserted
                id = available
            } else {
                id = candidate.id
            }
            if id != candidate.id { remappings[candidate.id] = id }
            reconciled.append(
                ApplicationRecord(
                    id: id, name: candidate.name,
                    bundleIdentifier: candidate.bundleIdentifier, url: candidate.url))
        }

        let currentIDs = Set(reconciled.map(\.id))
        return CatalogReconciliation(
            records: reconciled,
            removedIDs: Set(previous.map(\.id)).subtracting(currentIDs),
            idRemappings: remappings
        )
    }

    private static func canonicalURL(_ record: ApplicationRecord) -> String {
        record.url.standardizedFileURL.absoluteString
    }
}
