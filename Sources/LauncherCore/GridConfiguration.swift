import Foundation

/// The user's preferred grid density. Display fitting belongs to the presentation layer.
public struct GridConfiguration: Codable, Equatable, Sendable {
    public static let columnRange = 4...10
    public static let rowRange = 3...9
    public static let standard = GridConfiguration()

    public let columns: Int
    public let rows: Int

    public var capacity: Int { columns * rows }

    public init() {
        columns = 7
        rows = 5
    }

    public init(columns: Int, rows: Int) throws {
        guard Self.columnRange.contains(columns) else {
            throw ValidationError.columnsOutOfRange(columns)
        }
        guard Self.rowRange.contains(rows) else {
            throw ValidationError.rowsOutOfRange(rows)
        }
        self.columns = columns
        self.rows = rows
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            columns: container.decode(Int.self, forKey: .columns),
            rows: container.decode(Int.self, forKey: .rows)
        )
    }

    public enum ValidationError: Error, Equatable, Sendable {
        case columnsOutOfRange(Int)
        case rowsOutOfRange(Int)
    }
}
