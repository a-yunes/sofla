import Foundation

/// Only app-owned choices belong here. System appearance is deliberately not persisted.
/// PersistentDocument owns the storage schema and validation boundary.
public struct LauncherPreferences: Codable, Equatable, Sendable {
    public static let retentionDaysRange = 1...3_650
    public static let maximumCustomApplicationFolders = 64
    public static let maximumRecentsCountRange = 1...200
    public static let defaultMaximumRecentsCount = 50

    public var grid: GridConfiguration
    public var iconSize: IconSize
    public var showsFavorites: Bool
    public var showsRecents: Bool
    public var showsKeyboardHints: Bool
    public var startCollection: StartCollection
    public var typoTolerance: Bool
    public var recordsRecents: Bool
    public var recentsScope: RecentsScope
    public var retentionDays: Int
    public var maximumRecentsCount: Int
    public var dockIconAppearance: DockIconAppearance
    public var pageSwipeSensitivity: PageSwipeSensitivity
    public var customApplicationFolders: [URL]
    public var shortcut: HotKeyPreference

    public init(
        grid: GridConfiguration = .standard,
        iconSize: IconSize = .medium,
        showsFavorites: Bool = true,
        showsRecents: Bool = true,
        showsKeyboardHints: Bool = false,
        startCollection: StartCollection = .all,
        typoTolerance: Bool = true,
        recordsRecents: Bool = true,
        recentsScope: RecentsScope = .anywhere,
        retentionDays: Int = 30,
        maximumRecentsCount: Int = Self.defaultMaximumRecentsCount,
        dockIconAppearance: DockIconAppearance = .system,
        pageSwipeSensitivity: PageSwipeSensitivity = .standard,
        customApplicationFolders: [URL] = [],
        shortcut: HotKeyPreference = .optionSpace
    ) {
        self.grid = grid
        self.iconSize = iconSize
        self.showsFavorites = showsFavorites
        self.showsRecents = showsRecents
        self.showsKeyboardHints = showsKeyboardHints
        self.startCollection = startCollection
        self.typoTolerance = typoTolerance
        self.recordsRecents = recordsRecents
        self.recentsScope = recentsScope
        self.retentionDays = retentionDays
        self.maximumRecentsCount = maximumRecentsCount
        self.dockIconAppearance = dockIconAppearance
        self.pageSwipeSensitivity = pageSwipeSensitivity
        self.customApplicationFolders = customApplicationFolders
        self.shortcut = shortcut
    }

    public static func defaults(preservingShortcut shortcut: HotKeyPreference) -> Self {
        Self(shortcut: shortcut)
    }

    private init(
        validatingGrid grid: GridConfiguration,
        iconSize: IconSize,
        showsFavorites: Bool,
        showsRecents: Bool,
        showsKeyboardHints: Bool,
        startCollection: StartCollection,
        typoTolerance: Bool,
        recordsRecents: Bool,
        recentsScope: RecentsScope,
        retentionDays: Int,
        maximumRecentsCount: Int,
        dockIconAppearance: DockIconAppearance,
        pageSwipeSensitivity: PageSwipeSensitivity,
        customApplicationFolders: [URL],
        shortcut: HotKeyPreference
    ) throws {
        guard Self.retentionDaysRange.contains(retentionDays) else {
            throw ValidationError.retentionDaysOutOfRange(retentionDays)
        }
        guard Self.maximumRecentsCountRange.contains(maximumRecentsCount) else {
            throw ValidationError.maximumRecentsCountOutOfRange(maximumRecentsCount)
        }
        guard customApplicationFolders.count <= Self.maximumCustomApplicationFolders else {
            throw ValidationError.tooManyCustomApplicationFolders(customApplicationFolders.count)
        }
        guard
            Set(customApplicationFolders.map(\.standardizedFileURL)).count
                == customApplicationFolders.count
        else { throw ValidationError.duplicateCustomApplicationFolder }
        self.grid = grid
        self.iconSize = iconSize
        self.showsFavorites = showsFavorites
        self.showsRecents = showsRecents
        self.showsKeyboardHints = showsKeyboardHints
        self.startCollection = startCollection
        self.typoTolerance = typoTolerance
        self.recordsRecents = recordsRecents
        self.recentsScope = recentsScope
        self.retentionDays = retentionDays
        self.maximumRecentsCount = maximumRecentsCount
        self.dockIconAppearance = dockIconAppearance
        self.pageSwipeSensitivity = pageSwipeSensitivity
        self.customApplicationFolders = customApplicationFolders
        self.shortcut = shortcut
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            validatingGrid: container.decode(GridConfiguration.self, forKey: .grid),
            iconSize: container.decode(IconSize.self, forKey: .iconSize),
            showsFavorites: container.decode(Bool.self, forKey: .showsFavorites),
            showsRecents: container.decode(Bool.self, forKey: .showsRecents),
            showsKeyboardHints: container.decode(Bool.self, forKey: .showsKeyboardHints),
            startCollection: container.decode(StartCollection.self, forKey: .startCollection),
            typoTolerance: container.decode(Bool.self, forKey: .typoTolerance),
            recordsRecents: container.decode(Bool.self, forKey: .recordsRecents),
            recentsScope: container.decode(RecentsScope.self, forKey: .recentsScope),
            retentionDays: container.decode(Int.self, forKey: .retentionDays),
            maximumRecentsCount: container.decode(Int.self, forKey: .maximumRecentsCount),
            dockIconAppearance: container.decode(
                DockIconAppearance.self, forKey: .dockIconAppearance),
            pageSwipeSensitivity: container.decode(
                PageSwipeSensitivity.self, forKey: .pageSwipeSensitivity),
            customApplicationFolders: container.decode(
                [URL].self, forKey: .customApplicationFolders),
            shortcut: container.decode(HotKeyPreference.self, forKey: .shortcut)
        )
    }

    public func validate() throws {
        guard
            customApplicationFolders.allSatisfy({
                $0.isFileURL && !$0.path.contains("\0") && $0.path.utf8.count <= 4_096
            })
        else { throw ValidationError.invalidCustomApplicationFolder }
        guard Self.retentionDaysRange.contains(retentionDays) else {
            throw ValidationError.retentionDaysOutOfRange(retentionDays)
        }
        guard Self.maximumRecentsCountRange.contains(maximumRecentsCount) else {
            throw ValidationError.maximumRecentsCountOutOfRange(maximumRecentsCount)
        }
        guard customApplicationFolders.count <= Self.maximumCustomApplicationFolders else {
            throw ValidationError.tooManyCustomApplicationFolders(customApplicationFolders.count)
        }
        guard
            Set(customApplicationFolders.map(\.standardizedFileURL)).count
                == customApplicationFolders.count
        else { throw ValidationError.duplicateCustomApplicationFolder }
        try shortcut.validate()
    }

    public enum IconSize: String, Codable, CaseIterable, Sendable {
        case small
        case medium
        case large
    }

    public enum StartCollection: String, Codable, CaseIterable, Sendable {
        case all
        case favorites
        case recents
    }

    public enum RecentsScope: String, Codable, CaseIterable, Sendable {
        case anywhere
        case launcher
    }

    public enum DockIconAppearance: String, Codable, CaseIterable, Sendable {
        case system
        case light
        case dark
    }

    public enum PageSwipeSensitivity: String, Codable, CaseIterable, Sendable {
        case slow
        case standard
        case fast

        public var scrollThreshold: Double {
            switch self {
            case .slow: 18
            case .standard: 12
            case .fast: 7
            }
        }
    }

    public enum ValidationError: Error, Equatable, Sendable {
        case invalidCustomApplicationFolder
        case retentionDaysOutOfRange(Int)
        case maximumRecentsCountOutOfRange(Int)
        case tooManyCustomApplicationFolders(Int)
        case duplicateCustomApplicationFolder
    }
}

public struct HotKeyPreference: Codable, Equatable, Sendable {
    public static let commandModifier: UInt32 = 1 << 8
    public static let shiftModifier: UInt32 = 1 << 9
    public static let optionModifier: UInt32 = 1 << 11
    public static let controlModifier: UInt32 = 1 << 12
    public static let supportedModifiers =
        commandModifier | shiftModifier | optionModifier | controlModifier
    public static let optionSpace = HotKeyPreference(
        uncheckedKeyCode: 49, modifiers: optionModifier)

    public var keyCode: UInt32
    public var modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) throws {
        guard keyCode <= 127 else { throw ValidationError.unsupportedKeyCode(keyCode) }
        guard modifiers != 0, modifiers & ~Self.supportedModifiers == 0 else {
            throw ValidationError.unsupportedModifiers(modifiers)
        }
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            keyCode: container.decode(UInt32.self, forKey: .keyCode),
            modifiers: container.decode(UInt32.self, forKey: .modifiers)
        )
    }

    public func validate() throws {
        guard keyCode <= 127 else { throw ValidationError.unsupportedKeyCode(keyCode) }
        guard modifiers != 0, modifiers & ~Self.supportedModifiers == 0 else {
            throw ValidationError.unsupportedModifiers(modifiers)
        }
    }

    private init(uncheckedKeyCode: UInt32, modifiers: UInt32) {
        keyCode = uncheckedKeyCode
        self.modifiers = modifiers
    }

    public enum ValidationError: Error, Equatable, Sendable {
        case unsupportedKeyCode(UInt32)
        case unsupportedModifiers(UInt32)
    }
}
