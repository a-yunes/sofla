import Foundation

extension LibraryState {
    public func validate(allowMissingApplicationReferences: Bool = true) throws {
        try preferences.validate()
        let recordIDs = records.map(\.id)
        guard recordIDs.allSatisfy({ !$0.isEmpty }) else { throw LibraryError.emptyIdentifier }
        do {
            for record in records { try record.validate() }
            for record in retiredApplicationReferences { try record.validate() }
        } catch {
            throw LibraryError.invalidApplicationRecord
        }
        guard Set(recordIDs).count == recordIDs.count else { throw LibraryError.duplicateRecordID }
        let retiredIDs = retiredApplicationReferences.map(\.id)
        guard Set(retiredIDs).count == retiredIDs.count,
            Set(retiredIDs).isDisjoint(with: recordIDs),
            retiredApplicationReferences.count <= Self.maximumRetiredApplicationReferences
        else { throw LibraryError.invalidRetiredApplicationReferences }

        let folderIDs = folders.map(\.id)
        guard Set(folderIDs).count == folderIDs.count else { throw LibraryError.duplicateFolderID }
        let rootFolderIDs = rootOrder.compactMap { item -> String? in
            if case .folder(let id) = item { return id }
            return nil
        }
        guard Set(rootFolderIDs) == Set(folderIDs), rootFolderIDs.count == folderIDs.count else {
            throw LibraryError.invalidFolderReference
        }

        let placements =
            rootOrder.compactMap { item -> String? in
                if case .application(let id) = item { return id }
                return nil
            } + folders.flatMap(\.applicationIDs)
        guard Set(placements).count == placements.count else {
            throw LibraryError.duplicatePlacement
        }

        let known = Set(recordIDs)
        if !allowMissingApplicationReferences {
            let allReferences = Set(
                placements + favoriteIDs + aliases.keys + recents.map(\.applicationID)
            )
            .union(hiddenIDs)
            guard allReferences.isSubset(of: known) else {
                throw LibraryError.unknownApplicationReference
            }
        }
        guard Set(favoriteIDs).count == favoriteIDs.count else {
            throw LibraryError.duplicateFavorite
        }
        for values in aliases.values {
            try Self.validateAliases(values)
        }
        var aliasOwners: [String: String] = [:]
        for (applicationID, values) in aliases {
            for alias in values {
                let normalized = SearchEngine.normalize(alias)
                if let owner = aliasOwners[normalized], owner != applicationID {
                    throw LibraryError.aliasCollision(normalized)
                }
                aliasOwners[normalized] = applicationID
            }
        }
    }

    static func validateAliases(_ aliases: [String]) throws {
        let normalized = aliases.map(SearchEngine.normalize)
        guard normalized.allSatisfy({ !$0.isEmpty }) else { throw LibraryError.emptyAlias }
        guard Set(normalized).count == normalized.count else { throw LibraryError.duplicateAlias }
        guard aliases.count <= 32, aliases.allSatisfy({ $0.count <= 80 }) else {
            throw LibraryError.aliasLimitExceeded
        }
    }
}
