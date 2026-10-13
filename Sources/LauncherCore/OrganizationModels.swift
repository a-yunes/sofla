import Foundation

public enum LibraryItem: Codable, Equatable, Hashable, Sendable, Identifiable {
    case application(String)
    case folder(String)

    public var id: String {
        switch self {
        case .application(let id): "application:\(id)"
        case .folder(let id): "folder:\(id)"
        }
    }
}

public struct ApplicationFolder: Codable, Equatable, Sendable, Identifiable {
    public static let maximumNameLength = 80

    public let id: String
    public var name: String
    public var applicationIDs: [String]

    public init(id: String, name: String, applicationIDs: [String]) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LibraryError.emptyFolderName }
        guard trimmed.count <= Self.maximumNameLength else { throw LibraryError.folderNameTooLong }
        guard !id.isEmpty else { throw LibraryError.emptyIdentifier }
        guard Set(applicationIDs).count == applicationIDs.count else {
            throw LibraryError.duplicateReference
        }
        self.id = id
        self.name = trimmed
        self.applicationIDs = applicationIDs
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(String.self, forKey: .id),
            name: container.decode(String.self, forKey: .name),
            applicationIDs: container.decode([String].self, forKey: .applicationIDs)
        )
    }
}

public enum OrganizationOrderingMode: String, Codable, CaseIterable, Sendable {
    case automatic
    case manual
}

public struct OrganizationSnapshot: Codable, Equatable, Sendable {
    public var rootOrder: [LibraryItem]
    public var folders: [ApplicationFolder]
    public var favoriteIDs: [String]
    public var hiddenIDs: Set<String>
    public var aliases: [String: [String]]
    public var recents: [RecentApplication]
    public var orderingMode: OrganizationOrderingMode

    public init(
        rootOrder: [LibraryItem] = [],
        folders: [ApplicationFolder] = [],
        favoriteIDs: [String] = [],
        hiddenIDs: Set<String> = [],
        aliases: [String: [String]] = [:],
        recents: [RecentApplication] = [],
        orderingMode: OrganizationOrderingMode = .automatic
    ) {
        self.rootOrder = rootOrder
        self.folders = folders
        self.favoriteIDs = favoriteIDs
        self.hiddenIDs = hiddenIDs
        self.aliases = aliases
        self.recents = recents
        self.orderingMode = orderingMode
    }
}

public enum LibraryCommand: Equatable, Sendable {
    case restore(OrganizationSnapshot)
    case reorderRoot(itemID: String, destination: Int)
    case createFolder(id: String, name: String, applicationIDs: [String], destination: Int)
    case renameFolder(id: String, name: String)
    case ungroupFolder(id: String, destination: Int)
    case moveApplicationsToFolder(applicationIDs: [String], folderID: String, destination: Int)
    case moveApplicationsToRoot(applicationIDs: [String], destination: Int)
    case setFavorite(applicationID: String, isFavorite: Bool)
    case reorderFavorite(applicationID: String, destination: Int)
    case setHidden(applicationID: String, isHidden: Bool)
    case setAliases(applicationID: String, values: [String])
    case restoreAlphabeticalOrder
    case clearRecents
    case replaceRecents([RecentApplication])
    case resetOrganization
}

public enum LibraryError: Error, Equatable, Sendable {
    case emptyIdentifier
    case duplicateRecordID
    case invalidApplicationRecord
    case invalidRetiredApplicationReferences
    case duplicateFolderID
    case invalidFolderReference
    case duplicatePlacement
    case unknownApplicationReference
    case duplicateFavorite
    case duplicateReference
    case emptyFolderName
    case folderNameTooLong
    case folderRequiresApplications
    case folderNotFound
    case itemNotFound
    case emptyAlias
    case duplicateAlias
    case aliasLimitExceeded
    case aliasCollision(String)
    case recentHistoryLimitExceeded
}
