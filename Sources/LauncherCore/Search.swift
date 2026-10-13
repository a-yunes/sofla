import Foundation

public struct SearchResult: Equatable, Sendable, Identifiable {
    public enum MatchKind: Int, Equatable, Sendable {
        case exact
        case wordPrefix
        case prefix
        case substring
        case fuzzy
    }

    public let application: ApplicationRecord
    public let matchKind: MatchKind
    public let editDistance: Int
    public var id: String { application.id }
}

public enum SearchEngine {
    public static func search(
        query: String,
        in records: [ApplicationRecord],
        aliases: [String: [String]] = [:],
        hiddenIDs: Set<String> = [],
        typoTolerance: Bool = true,
        limit: Int? = nil
    ) -> [SearchResult] {
        SearchIndex(records: records, aliases: aliases, hiddenIDs: hiddenIDs)
            .search(query, typoTolerance: typoTolerance, limit: limit)
    }

    public static func normalize(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        .split(whereSeparator: \.isWhitespace)
        .joined(separator: " ")
    }

}

/// Precomputes catalog text so the keystroke path performs no filesystem work or repeated
/// normalization. Rebuild when records, aliases, or hidden identifiers change.
public struct SearchIndex: Sendable {
    private struct IndexedTerm: Sendable {
        let value: String
        let characters: [Character]
        let sourcePriority: Int
    }

    private struct IndexedRecord: Sendable {
        let record: ApplicationRecord
        let terms: [IndexedTerm]
        let normalizedName: String
    }

    private struct RankedResult {
        let record: ApplicationRecord
        let kind: SearchResult.MatchKind
        let distance: Int
        let source: Int
        let normalizedName: String
    }

    private let records: [IndexedRecord]

    public init(
        records: [ApplicationRecord], aliases: [String: [String]] = [:],
        hiddenIDs: Set<String> = []
    ) {
        self.records = records.filter { !hiddenIDs.contains($0.id) }.map { record in
            let filename = record.url.deletingPathExtension().lastPathComponent
            let rawTerms =
                [(record.name, 0), (filename, 1)]
                + (aliases[record.id] ?? []).map { ($0, 0) }
            let terms = rawTerms.map { value, priority -> IndexedTerm in
                let normalized = SearchEngine.normalize(value)
                return IndexedTerm(
                    value: normalized, characters: Array(normalized), sourcePriority: priority)
            }
            return IndexedRecord(
                record: record, terms: terms, normalizedName: SearchEngine.normalize(record.name))
        }
        .sorted {
            ($0.normalizedName, $0.record.url.absoluteString, $0.record.id)
                < ($1.normalizedName, $1.record.url.absoluteString, $1.record.id)
        }
    }

    public func search(
        _ query: String, typoTolerance: Bool = true, limit: Int? = nil
    ) -> [SearchResult] {
        let needle = SearchEngine.normalize(query)
        let count = Self.validLimit(limit, count: records.count)
        guard !needle.isEmpty else {
            return records.prefix(count).map {
                SearchResult(application: $0.record, matchKind: .prefix, editDistance: 0)
            }
        }

        let needleCharacters = Array(needle)
        let matches = records.compactMap { indexed -> RankedResult? in
            let best = indexed.terms.compactMap { term in
                rank(
                    needle: needle, needleCharacters: needleCharacters, candidate: term,
                    typoTolerance: typoTolerance
                ).map { ($0.kind, $0.distance, term.sourcePriority) }
            }.min { lhs, rhs in
                (lhs.0.rawValue, lhs.1, lhs.2) < (rhs.0.rawValue, rhs.1, rhs.2)
            }
            return best.map {
                RankedResult(
                    record: indexed.record, kind: $0.0, distance: $0.1, source: $0.2,
                    normalizedName: indexed.normalizedName)
            }
        }.sorted { lhs, rhs in
            let left = (
                lhs.kind.rawValue, lhs.distance, lhs.source, lhs.normalizedName,
                lhs.record.url.absoluteString, lhs.record.id
            )
            let right = (
                rhs.kind.rawValue, rhs.distance, rhs.source, rhs.normalizedName,
                rhs.record.url.absoluteString, rhs.record.id
            )
            return left < right
        }

        return matches.prefix(Self.validLimit(limit, count: matches.count)).map {
            SearchResult(application: $0.record, matchKind: $0.kind, editDistance: $0.distance)
        }
    }

    private func rank(
        needle: String, needleCharacters: [Character], candidate: IndexedTerm,
        typoTolerance: Bool
    ) -> (kind: SearchResult.MatchKind, distance: Int)? {
        if candidate.value == needle { return (.exact, 0) }
        if candidate.value.split(separator: " ").contains(where: { $0.hasPrefix(needle) }) {
            return (.wordPrefix, 0)
        }
        if candidate.value.hasPrefix(needle) { return (.prefix, 0) }
        if candidate.value.contains(needle) { return (.substring, 0) }
        guard typoTolerance else { return nil }
        let maximumDistance = needle.count < 5 ? 1 : 2
        let distance = boundedEditDistance(
            needleCharacters, candidate.characters, maximum: maximumDistance)
        return distance.map { (.fuzzy, $0) }
    }

    private func boundedEditDistance(
        _ left: [Character], _ right: [Character], maximum: Int
    ) -> Int? {
        guard abs(left.count - right.count) <= maximum else { return nil }
        var previous = Array(0...right.count)
        for (i, leftCharacter) in left.enumerated() {
            var current = [i + 1]
            var rowMinimum = i + 1
            for (j, rightCharacter) in right.enumerated() {
                let value = min(
                    previous[j + 1] + 1,
                    current[j] + 1,
                    previous[j] + (leftCharacter == rightCharacter ? 0 : 1)
                )
                current.append(value)
                rowMinimum = min(rowMinimum, value)
            }
            if rowMinimum > maximum { return nil }
            previous = current
        }
        return previous.last.flatMap { $0 <= maximum ? $0 : nil }
    }

    private static func validLimit(_ limit: Int?, count: Int) -> Int {
        min(max(limit ?? count, 0), count)
    }
}
