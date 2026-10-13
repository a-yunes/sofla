import Foundation
import Testing

@testable import LauncherCore

struct GridConfigurationTests {
    @Test(arguments: [4, 7, 10], [3, 5, 9])
    func acceptsSupportedDensity(columns: Int, rows: Int) throws {
        let grid = try GridConfiguration(columns: columns, rows: rows)
        #expect(grid.capacity == columns * rows)
    }

    @Test(arguments: [Int.min, -1, 0, 3, 11, Int.max])
    func rejectsInvalidColumns(columns: Int) {
        #expect(throws: GridConfiguration.ValidationError.columnsOutOfRange(columns)) {
            try GridConfiguration(columns: columns, rows: 5)
        }
    }

    @Test(arguments: [Int.min, -1, 0, 2, 10, Int.max])
    func rejectsInvalidRows(rows: Int) {
        #expect(throws: GridConfiguration.ValidationError.rowsOutOfRange(rows)) {
            try GridConfiguration(columns: 7, rows: rows)
        }
    }

    @Test
    func persistedValuesCannotBypassValidation() {
        let invalid = Data(#"{"columns":0,"rows":5}"#.utf8)
        #expect(throws: GridConfiguration.ValidationError.columnsOutOfRange(0)) {
            try JSONDecoder().decode(GridConfiguration.self, from: invalid)
        }
    }

    @Test
    func missingDimensionsAreNotSilentlyDefaulted() {
        let incomplete = Data(#"{"columns":7}"#.utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(GridConfiguration.self, from: incomplete)
        }
    }
}
