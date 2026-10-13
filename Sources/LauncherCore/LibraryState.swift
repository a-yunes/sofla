import Foundation

public struct LibraryState: Equatable, Sendable {
    public static let maximumRetiredApplicationReferences = 1_000

    public var records: [ApplicationRecord]
    public var preferences: LauncherPreferences
    public private(set) var retiredApplicationReferences: [ApplicationRecord]
    public private(set) var rootOrder: [LibraryItem]
    public private(set) var orderingMode: OrganizationOrderingMode
    public private(set) var folders: [ApplicationFolder]
    public private(set) var favoriteIDs: [String]
    public private(set) var hiddenIDs: Set<String>
    public private(set) var aliases: [String: [String]]
    public private(set) var recents: [RecentApplication]

    public init(
        records: [ApplicationRecord] = [],
        preferences: LauncherPreferences = LauncherPreferences(),
        organization: OrganizationSnapshot? = nil,
        retiredApplicationReferences: [ApplicationRecord] = []
    ) throws {
        self.records = records
        self.preferences = preferences
        let activeIDs = Set(records.map(\.id))
        self.retiredApplicationReferences = retiredApplicationReferences.filter {
            !activeIDs.contains($0.id)
        }
        let organization =
            organization
            ?? OrganizationSnapshot(
                rootOrder: records.map { .application($0.id) }
            )
        rootOrder = organization.rootOrder
        orderingMode = organization.orderingMode
        folders = organization.folders
        favoriteIDs = organization.favoriteIDs
        hiddenIDs = organization.hiddenIDs
        aliases = organization.aliases
        recents = organization.recents
        let placed = placedApplicationIDs()
        rootOrder.append(
            contentsOf: records.lazy.map(\.id).filter { !placed.contains($0) }.map(
                LibraryItem.application))
        if orderingMode == .automatic {
            sortAlphabetically()
        }
        trimRetiredApplicationReferences()
        try validate()
    }

    public var applicationReferences: [ApplicationRecord] {
        let activeIDs = Set(records.map(\.id))
        return records + retiredApplicationReferences.filter { !activeIDs.contains($0.id) }
    }

    public var organization: OrganizationSnapshot {
        OrganizationSnapshot(
            rootOrder: rootOrder,
            folders: folders,
            favoriteIDs: favoriteIDs,
            hiddenIDs: hiddenIDs,
            aliases: aliases,
            recents: recents,
            orderingMode: orderingMode
        )
    }

    public var visibleRecords: [ApplicationRecord] {
        records.filter { !hiddenIDs.contains($0.id) }
    }

    public func search(_ query: String, limit: Int? = nil) -> [SearchResult] {
        SearchEngine.search(
            query: query,
            in: records,
            aliases: aliases,
            hiddenIDs: hiddenIDs,
            typoTolerance: preferences.typoTolerance,
            limit: limit
        )
    }

    @discardableResult
    public mutating func apply(_ command: LibraryCommand) throws -> LibraryCommand {
        let before = organization
        do {
            try perform(command)
            try validate()
        } catch {
            restore(before)
            throw error
        }
        return .restore(before)
    }

    public mutating func reconcileCatalog(_ discovered: [ApplicationRecord]) throws
        -> CatalogReconciliation
    {
        var candidate = self
        let result = try candidate.reconcileInPlace(discovered)
        self = candidate
        return result
    }

    private mutating func reconcileInPlace(_ discovered: [ApplicationRecord]) throws
        -> CatalogReconciliation
    {
        let discoveredIDs = discovered.map(\.id)
        guard Set(discoveredIDs).count == discoveredIDs.count else {
            throw LibraryError.duplicateRecordID
        }
        for record in discovered { try record.validate() }
        let previouslyActiveIDs = Set(records.map(\.id))
        let previousReferences = applicationReferences
        let reconciliation = CatalogReconciler.reconcile(
            previous: previousReferences, discovered: discovered)
        records = reconciliation.records
        let activeIDs = Set(records.map(\.id))
        retiredApplicationReferences.removeAll { activeIDs.contains($0.id) }
        let retainedIDs = Set(retiredApplicationReferences.map(\.id))
        retiredApplicationReferences.append(
            contentsOf: previousReferences.filter {
                reconciliation.removedIDs.contains($0.id) && !retainedIDs.contains($0.id)
            })
        trimRetiredApplicationReferences()
        let placed = placedApplicationIDs()
        rootOrder.append(
            contentsOf: records.lazy.map(\.id).filter { !placed.contains($0) }.map(
                LibraryItem.application))
        if orderingMode == .automatic {
            sortAlphabetically()
        }
        try validate(allowMissingApplicationReferences: true)
        return CatalogReconciliation(
            records: reconciliation.records,
            removedIDs: previouslyActiveIDs.subtracting(activeIDs),
            idRemappings: reconciliation.idRemappings)
    }

    private mutating func perform(_ command: LibraryCommand) throws {
        switch command {
        case .restore(let snapshot): restore(snapshot)
        case .reorderRoot(let itemID, let destination):
            guard let source = rootOrder.firstIndex(where: { $0.id == itemID }) else {
                throw LibraryError.itemNotFound
            }
            orderingMode = .manual
            let item = rootOrder.remove(at: source)
            rootOrder.insert(item, at: min(max(destination, 0), rootOrder.count))
        case .createFolder(let id, let name, let applicationIDs, let destination):
            guard !folders.contains(where: { $0.id == id }) else {
                throw LibraryError.duplicateFolderID
            }
            guard applicationIDs.count >= 2 else { throw LibraryError.folderRequiresApplications }
            orderingMode = .manual
            try removeFromPlacements(applicationIDs)
            removeEmptyFolders()
            let folder = try ApplicationFolder(id: id, name: name, applicationIDs: applicationIDs)
            folders.append(folder)
            rootOrder.insert(.folder(id), at: min(max(destination, 0), rootOrder.count))
        case .renameFolder(let id, let name):
            guard let index = folders.firstIndex(where: { $0.id == id }) else {
                throw LibraryError.folderNotFound
            }
            folders[index] = try ApplicationFolder(
                id: id, name: name, applicationIDs: folders[index].applicationIDs)
        case .ungroupFolder(let id, let destination):
            guard let folderIndex = folders.firstIndex(where: { $0.id == id }) else {
                throw LibraryError.folderNotFound
            }
            orderingMode = .manual
            let applicationIDs = folders.remove(at: folderIndex).applicationIDs
            rootOrder.removeAll { $0 == .folder(id) }
            let index = min(max(destination, 0), rootOrder.count)
            rootOrder.insert(contentsOf: applicationIDs.map(LibraryItem.application), at: index)
        case .moveApplicationsToFolder(let applicationIDs, let folderID, let destination):
            guard folders.contains(where: { $0.id == folderID }) else {
                throw LibraryError.folderNotFound
            }
            guard !applicationIDs.isEmpty else { return }
            orderingMode = .manual
            try removeFromPlacements(applicationIDs)
            removeEmptyFolders()
            guard let folderIndex = folders.firstIndex(where: { $0.id == folderID }) else {
                throw LibraryError.folderNotFound
            }
            let index = min(max(destination, 0), folders[folderIndex].applicationIDs.count)
            folders[folderIndex].applicationIDs.insert(contentsOf: applicationIDs, at: index)
        case .moveApplicationsToRoot(let applicationIDs, let destination):
            guard !applicationIDs.isEmpty else { return }
            orderingMode = .manual
            try removeFromPlacements(applicationIDs)
            removeEmptyFolders()
            let index = min(max(destination, 0), rootOrder.count)
            rootOrder.insert(contentsOf: applicationIDs.map(LibraryItem.application), at: index)
        case .setFavorite(let applicationID, let isFavorite):
            try requireRecord(applicationID)
            favoriteIDs.removeAll { $0 == applicationID }
            if isFavorite { favoriteIDs.append(applicationID) }
        case .reorderFavorite(let applicationID, let destination):
            guard let source = favoriteIDs.firstIndex(of: applicationID) else {
                throw LibraryError.itemNotFound
            }
            favoriteIDs.remove(at: source)
            favoriteIDs.insert(applicationID, at: min(max(destination, 0), favoriteIDs.count))
        case .setHidden(let applicationID, let isHidden):
            try requireRecord(applicationID)
            if isHidden { hiddenIDs.insert(applicationID) } else { hiddenIDs.remove(applicationID) }
        case .setAliases(let applicationID, let values):
            try requireRecord(applicationID)
            try Self.validateAliases(values)
            if values.isEmpty {
                aliases.removeValue(forKey: applicationID)
            } else {
                aliases[applicationID] = values
            }
        case .restoreAlphabeticalOrder:
            sortAlphabetically()
            orderingMode = .automatic
        case .clearRecents: recents.removeAll()
        case .replaceRecents(let values): recents = values
        case .resetOrganization:
            rootOrder = records.map { .application($0.id) }
            folders.removeAll()
            favoriteIDs.removeAll()
            hiddenIDs.removeAll()
            aliases.removeAll()
            recents.removeAll()
            orderingMode = .automatic
            sortAlphabetically()
        }
    }

    private mutating func restore(_ snapshot: OrganizationSnapshot) {
        rootOrder = snapshot.rootOrder
        orderingMode = snapshot.orderingMode
        folders = snapshot.folders
        favoriteIDs = snapshot.favoriteIDs
        hiddenIDs = snapshot.hiddenIDs
        aliases = snapshot.aliases
        recents = snapshot.recents
    }

    private mutating func removeFromPlacements(_ applicationIDs: [String]) throws {
        guard Set(applicationIDs).count == applicationIDs.count else {
            throw LibraryError.duplicateReference
        }
        for id in applicationIDs { try requireRecord(id) }
        let ids = Set(applicationIDs)
        rootOrder.removeAll {
            if case .application(let id) = $0 { return ids.contains(id) }
            return false
        }
        for index in folders.indices {
            folders[index].applicationIDs.removeAll { ids.contains($0) }
        }
    }

    private mutating func removeEmptyFolders() {
        let emptyIDs = Set(folders.filter(\.applicationIDs.isEmpty).map(\.id))
        folders.removeAll { emptyIDs.contains($0.id) }
        rootOrder.removeAll {
            if case .folder(let id) = $0 { return emptyIDs.contains(id) }
            return false
        }
    }

    private func requireRecord(_ id: String) throws {
        guard records.contains(where: { $0.id == id }) else {
            throw LibraryError.unknownApplicationReference
        }
    }

    private func placedApplicationIDs() -> Set<String> {
        Set(
            rootOrder.compactMap { item -> String? in
                if case .application(let id) = item { return id }
                return nil
            } + folders.flatMap(\.applicationIDs))
    }

    private mutating func trimRetiredApplicationReferences() {
        let referenced = organizationApplicationIDs()
        while retiredApplicationReferences.count > Self.maximumRetiredApplicationReferences {
            if let unused = retiredApplicationReferences.firstIndex(where: {
                !referenced.contains($0.id)
            }) {
                retiredApplicationReferences.remove(at: unused)
            } else {
                retiredApplicationReferences.removeFirst()
            }
        }
    }

    private func organizationApplicationIDs() -> Set<String> {
        Set(
            rootOrder.compactMap { item -> String? in
                if case .application(let id) = item { return id }
                return nil
            } + folders.flatMap(\.applicationIDs) + favoriteIDs + aliases.keys
                + recents.map(\.applicationID)
        ).union(hiddenIDs)
    }

    private mutating func sortAlphabetically() {
        let names = Dictionary(
            applicationReferences.map {
                ($0.id, SearchEngine.normalize($0.name))
            },
            uniquingKeysWith: { first, _ in first }
        )
        let folderNames = Dictionary(
            folders.map { ($0.id, SearchEngine.normalize($0.name)) },
            uniquingKeysWith: { first, _ in first }
        )
        rootOrder.sort {
            let lhs = Self.sortName($0, appNames: names, folderNames: folderNames)
            let rhs = Self.sortName($1, appNames: names, folderNames: folderNames)
            return (lhs, $0.id) < (rhs, $1.id)
        }
        for index in folders.indices {
            folders[index].applicationIDs.sort {
                let lhs = names[$0] ?? $0
                let rhs = names[$1] ?? $1
                return (lhs, $0) < (rhs, $1)
            }
        }
    }

    private static func sortName(
        _ item: LibraryItem, appNames: [String: String], folderNames: [String: String]
    ) -> String {
        switch item {
        case .application(let id): appNames[id] ?? id
        case .folder(let id): folderNames[id] ?? id
        }
    }
}
