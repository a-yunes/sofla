import CoreGraphics
import LauncherCore
import Testing

@testable import AppLauncher

@Suite
struct DisplayGridTests {
    @Test
    func preferredGridFitsMeasuredRemainingHeightIncludingSpacing() {
        let available = CGSize(width: 1_350, height: 620)
        let grid = DisplayGrid(size: available, preferences: LauncherPreferences())

        #expect(grid.columns == 7)
        #expect(grid.rows == 5)
        let occupiedHeight =
            CGFloat(grid.rows) * grid.cellHeight
            + CGFloat(grid.rows - 1) * DisplayGrid.rowSpacing + DisplayGrid.topInset
        #expect(occupiedHeight <= available.height)
    }

    @Test
    func constrainedAndLargeRegionsRemainWithinPreferenceBounds() throws {
        let maximum = LauncherPreferences(
            grid: try GridConfiguration(columns: 10, rows: 9), iconSize: .large)
        let constrained = DisplayGrid(
            size: CGSize(width: 500, height: 180), preferences: maximum)
        #expect((1...10).contains(constrained.columns))
        #expect((1...9).contains(constrained.rows))
        #expect(constrained.iconSize > 0)

        let large = DisplayGrid(size: CGSize(width: 2_560, height: 2_000), preferences: maximum)
        #expect(large.columns == 10)
        #expect(large.rows == 9)
    }

    @Test
    func smallFolderUsesCompactRowsWithinMeasuredRegion() {
        let available = CGSize(width: 1_350, height: 620)
        let grid = DisplayGrid(
            size: available, preferences: LauncherPreferences(), compactItemCount: 2)

        #expect(grid.columns == 2)
        #expect(grid.rows == 1)
        #expect(grid.contentWidth == 360)
        #expect(grid.contentHeight < available.height)
    }
}
