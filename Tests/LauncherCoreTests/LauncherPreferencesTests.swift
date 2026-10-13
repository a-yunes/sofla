import Foundation
import Testing

@testable import LauncherCore

struct LauncherPreferencesTests {
    @Test
    func defaultsContainValidatedFeedbackPoliciesAndCanPreserveShortcut() throws {
        let defaults = LauncherPreferences()
        #expect(defaults.maximumRecentsCount == 50)
        #expect(defaults.dockIconAppearance == .system)
        #expect(defaults.pageSwipeSensitivity == .standard)
        #expect(defaults.pageSwipeSensitivity.scrollThreshold == 12)
        #expect(LauncherPreferences.PageSwipeSensitivity.slow.scrollThreshold == 18)
        #expect(LauncherPreferences.PageSwipeSensitivity.fast.scrollThreshold == 7)

        let shortcut = try HotKeyPreference(
            keyCode: 36, modifiers: HotKeyPreference.commandModifier)
        let restored = LauncherPreferences.defaults(preservingShortcut: shortcut)
        #expect(restored.shortcut == shortcut)
        #expect(restored.maximumRecentsCount == defaults.maximumRecentsCount)
        #expect(restored.grid == defaults.grid)
    }

    @Test
    func customFoldersMustBeLocalFileURLs() throws {
        var preferences = LauncherPreferences()
        preferences.customApplicationFolders = [
            try #require(URL(string: "https://example.com/apps"))
        ]
        #expect(throws: LauncherPreferences.ValidationError.invalidCustomApplicationFolder) {
            try preferences.validate()
        }
    }

    @Test
    func customizedLayoutSurvivesEncoding() throws {
        let preferences = LauncherPreferences(
            grid: try GridConfiguration(columns: 9, rows: 6),
            iconSize: .small,
            showsFavorites: false,
            showsRecents: true,
            showsKeyboardHints: true
        )
        let encoded = try JSONEncoder().encode(preferences)
        let decoded = try JSONDecoder().decode(LauncherPreferences.self, from: encoded)
        #expect(decoded == preferences)
    }

    @Test
    func preferencesContainOnlyAppOwnedChoices() throws {
        let data = try JSONEncoder().encode(LauncherPreferences())
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(
            Set(object.keys) == [
                "grid", "iconSize", "showsFavorites", "showsRecents", "showsKeyboardHints",
                "startCollection", "typoTolerance", "recordsRecents", "recentsScope",
                "retentionDays", "maximumRecentsCount", "dockIconAppearance",
                "pageSwipeSensitivity", "customApplicationFolders", "shortcut",
            ])
    }

    @Test
    func invalidPersistedGridIsReportedToStorageOwner() throws {
        let encoded = try JSONEncoder().encode(LauncherPreferences())
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["grid"] = ["columns": 7, "rows": 99]
        let data = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: GridConfiguration.ValidationError.rowsOutOfRange(99)) {
            try JSONDecoder().decode(LauncherPreferences.self, from: data)
        }
    }

    @Test
    func persistedRetentionAndShortcutAreValidated() throws {
        var preferences = LauncherPreferences()
        preferences.retentionDays = 0
        #expect(throws: LauncherPreferences.ValidationError.retentionDaysOutOfRange(0)) {
            try preferences.validate()
        }

        let encoded = try JSONEncoder().encode(LauncherPreferences())
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["shortcut"] = ["keyCode": 49, "modifiers": UInt32.max]
        let invalid = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: HotKeyPreference.ValidationError.unsupportedModifiers(UInt32.max)) {
            try JSONDecoder().decode(LauncherPreferences.self, from: invalid)
        }

        preferences = LauncherPreferences()
        preferences.maximumRecentsCount = 0
        #expect(
            throws: LauncherPreferences.ValidationError.maximumRecentsCountOutOfRange(0)
        ) {
            try preferences.validate()
        }
        preferences.maximumRecentsCount = 201
        #expect(
            throws: LauncherPreferences.ValidationError.maximumRecentsCountOutOfRange(201)
        ) {
            try preferences.validate()
        }
    }

    @Test
    func newlyAddedPreferenceKeysAreRequiredByTheDevelopmentSchema() throws {
        let encoded = try JSONEncoder().encode(LauncherPreferences())
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "maximumRecentsCount")
        let missingMaximum = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(LauncherPreferences.self, from: missingMaximum)
        }

        object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "pageSwipeSensitivity")
        let missingSensitivity = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(LauncherPreferences.self, from: missingSensitivity)
        }
    }
}
