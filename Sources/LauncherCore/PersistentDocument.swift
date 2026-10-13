import Foundation

public struct PersistentDocument: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var preferences: LauncherPreferences
    public var organization: OrganizationSnapshot
    public var applicationReferences: [ApplicationRecord]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        preferences: LauncherPreferences = LauncherPreferences(),
        organization: OrganizationSnapshot = OrganizationSnapshot(),
        applicationReferences: [ApplicationRecord] = []
    ) throws {
        self.schemaVersion = schemaVersion
        self.preferences = preferences
        self.organization = organization
        self.applicationReferences = applicationReferences
        try validate()
    }

    public func validate() throws {
        guard schemaVersion > 0 else {
            throw PersistentDocumentError.invalidSchemaVersion(schemaVersion)
        }
        guard schemaVersion <= Self.currentSchemaVersion else {
            throw PersistentDocumentError.futureSchema(
                found: schemaVersion, supported: Self.currentSchemaVersion)
        }
        do {
            try preferences.validate()
        } catch {
            throw PersistentDocumentError.invalidPreferences
        }
        let referenceIDs = applicationReferences.map(\.id)
        guard Set(referenceIDs).count == referenceIDs.count else {
            throw PersistentDocumentError.invalidApplicationReferences
        }
        do {
            for reference in applicationReferences { try reference.validate() }
        } catch {
            throw PersistentDocumentError.invalidApplicationReferences
        }
        let folderIDs = organization.folders.map(\.id)
        guard Set(folderIDs).count == folderIDs.count else {
            throw PersistentDocumentError.invalidOrganization(.duplicateFolderID)
        }
        let rootFolderIDs = organization.rootOrder.compactMap { item -> String? in
            if case .folder(let id) = item { return id }
            return nil
        }
        guard rootFolderIDs.count == folderIDs.count, Set(rootFolderIDs) == Set(folderIDs) else {
            throw PersistentDocumentError.invalidOrganization(.invalidFolderReference)
        }
        let placements =
            organization.rootOrder.compactMap { item -> String? in
                if case .application(let id) = item { return id }
                return nil
            } + organization.folders.flatMap(\.applicationIDs)
        guard placements.allSatisfy({ !$0.isEmpty }) else {
            throw PersistentDocumentError.invalidOrganization(.emptyIdentifier)
        }
        guard Set(placements).count == placements.count else {
            throw PersistentDocumentError.invalidOrganization(.duplicatePlacement)
        }
        guard Set(organization.favoriteIDs).count == organization.favoriteIDs.count else {
            throw PersistentDocumentError.invalidOrganization(.duplicateFavorite)
        }
        guard organization.recents.count <= RecentsPolicy.maximumHistoryLimit else {
            throw PersistentDocumentError.invalidOrganization(.recentHistoryLimitExceeded)
        }
        guard organization.recents.allSatisfy({ !$0.applicationID.isEmpty }) else {
            throw PersistentDocumentError.invalidOrganization(.emptyIdentifier)
        }
        guard organization.aliases.keys.allSatisfy({ !$0.isEmpty }) else {
            throw PersistentDocumentError.invalidOrganization(.emptyIdentifier)
        }
        for values in organization.aliases.values {
            let normalized = values.map(SearchEngine.normalize)
            guard normalized.allSatisfy({ !$0.isEmpty }) else {
                throw PersistentDocumentError.invalidOrganization(.emptyAlias)
            }
            guard Set(normalized).count == normalized.count else {
                throw PersistentDocumentError.invalidOrganization(.duplicateAlias)
            }
            guard values.count <= 32, values.allSatisfy({ $0.count <= 80 }) else {
                throw PersistentDocumentError.invalidOrganization(.aliasLimitExceeded)
            }
        }
        var aliasOwners: [String: String] = [:]
        for (applicationID, values) in organization.aliases {
            for alias in values {
                let normalized = SearchEngine.normalize(alias)
                if let owner = aliasOwners[normalized], owner != applicationID {
                    throw PersistentDocumentError.invalidOrganization(.aliasCollision(normalized))
                }
                aliasOwners[normalized] = applicationID
            }
        }
    }

    public func libraryState(records: [ApplicationRecord]) throws -> LibraryState {
        let reconciled: [ApplicationRecord]
        let retired: [ApplicationRecord]
        if records.isEmpty {
            reconciled = applicationReferences
            retired = []
        } else {
            let result = CatalogReconciler.reconcile(
                previous: applicationReferences, discovered: records)
            reconciled = result.records
            let activeIDs = Set(reconciled.map(\.id))
            retired = applicationReferences.filter { !activeIDs.contains($0.id) }
        }
        return try LibraryState(
            records: reconciled, preferences: preferences, organization: organization,
            retiredApplicationReferences: retired)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            schemaVersion: container.decode(Int.self, forKey: .schemaVersion),
            preferences: container.decode(LauncherPreferences.self, forKey: .preferences),
            organization: container.decode(OrganizationSnapshot.self, forKey: .organization),
            applicationReferences: container.decode(
                [ApplicationRecord].self, forKey: .applicationReferences)
        )
    }
}

public enum PersistentDocumentCodec {
    public static func encode(_ document: PersistentDocument) throws -> Data {
        try document.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(document)
    }

    public static func decode(_ data: Data) throws -> PersistentDocument {
        do {
            let document = try JSONDecoder().decode(PersistentDocument.self, from: data)
            try document.validate()
            return document
        } catch let error as PersistentDocumentError {
            throw error
        } catch is LauncherPreferences.ValidationError {
            throw PersistentDocumentError.invalidPreferences
        } catch is HotKeyPreference.ValidationError {
            throw PersistentDocumentError.invalidPreferences
        } catch is GridConfiguration.ValidationError {
            throw PersistentDocumentError.invalidPreferences
        } catch let error as LibraryError {
            throw PersistentDocumentError.invalidOrganization(error)
        } catch {
            throw PersistentDocumentError.malformed
        }
    }

    public static func encodeForExport(_ document: PersistentDocument) throws -> Data {
        var exported = document
        exported.organization.recents = []
        return try encode(exported)
    }
}

public enum PersistentDocumentError: Error, Equatable, Sendable {
    case malformed
    case invalidSchemaVersion(Int)
    case futureSchema(found: Int, supported: Int)
    case invalidPreferences
    case invalidApplicationReferences
    case invalidOrganization(LibraryError)
}
