import Foundation
import Testing

@testable import LauncherCore

struct SearchTests {
    private let records = [
        ApplicationRecord(
            id: "safari", name: "Safari", bundleIdentifier: nil,
            url: URL(fileURLWithPath: "/Safari.app")),
        ApplicationRecord(
            id: "tech", name: "Safari Technology Preview", bundleIdentifier: nil,
            url: URL(fileURLWithPath: "/Safari Technology Preview.app")),
        ApplicationRecord(
            id: "notes", name: "Quick Notes", bundleIdentifier: nil,
            url: URL(fileURLWithPath: "/Notes.app")),
        ApplicationRecord(
            id: "resume", name: "Résumé Builder", bundleIdentifier: nil,
            url: URL(fileURLWithPath: "/Resume.app")),
    ]

    @Test
    func rankingIsExactThenWordPrefixThenSubstring() {
        let result = SearchEngine.search(query: "safari", in: records)
        #expect(result.map(\.application.id) == ["safari", "tech"])
        #expect(result.map(\.matchKind) == [.exact, .wordPrefix])
    }

    @Test
    func aliasesDiacriticsWhitespaceAndHiddenPolicyApply() {
        #expect(
            SearchEngine.search(query: "  resume ", in: records).first?.application.id == "resume")
        let aliases = ["notes": ["scratch pad"]]
        #expect(
            SearchEngine.search(query: "scratch pad", in: records, aliases: aliases).first?
                .application.id == "notes")
        #expect(
            SearchEngine.search(query: "safari", in: records, hiddenIDs: ["safari"]).map(
                \.application.id) == ["tech"])
    }

    @Test
    func typoToleranceIsBoundedAndCanBeDisabled() {
        #expect(SearchEngine.search(query: "safri", in: records).first?.application.id == "safari")
        #expect(SearchEngine.search(query: "safri", in: records, typoTolerance: false).isEmpty)
        #expect(SearchEngine.search(query: "zzzzzz", in: records).isEmpty)
    }

    @Test
    func emptyQueryAndTiesAreStable() {
        let duplicates = [
            ApplicationRecord(
                id: "z", name: "Same", bundleIdentifier: nil, url: URL(fileURLWithPath: "/Z.app")),
            ApplicationRecord(
                id: "a", name: "Same", bundleIdentifier: nil, url: URL(fileURLWithPath: "/A.app")),
        ]
        #expect(SearchEngine.search(query: "", in: duplicates).map(\.id) == ["a", "z"])
        #expect(SearchEngine.search(query: "same", in: duplicates, limit: 1).map(\.id) == ["a"])
    }
}
