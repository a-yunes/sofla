import CoreGraphics
import LauncherCore

nonisolated struct DisplayGrid {
    static let rowSpacing: CGFloat = 8
    static let topInset: CGFloat = 6

    let columns: Int
    let rows: Int
    let iconSize: CGFloat
    let cellWidth: CGFloat
    let cellHeight: CGFloat
    let contentWidth: CGFloat

    var contentHeight: CGFloat {
        CGFloat(rows) * cellHeight + CGFloat(rows - 1) * Self.rowSpacing
    }

    init(size: CGSize, preferences: LauncherPreferences, compactItemCount: Int? = nil) {
        let base: CGFloat
        switch preferences.iconSize {
        case .small: base = 60
        case .medium: base = 76
        case .large: base = 94
        }
        let displayScale = min(1.5, max(1, size.width / 1440))
        let desired = base * displayScale
        let maximumColumns = min(
            preferences.grid.columns, max(1, compactItemCount ?? preferences.grid.columns))
        let availableWidth = min(
            max(100, size.width * 0.84),
            compactItemCount == nil ? .greatestFiniteMagnitude : CGFloat(maximumColumns) * 180)
        let availableHeight = max(120, size.height - Self.topInset)
        columns = min(maximumColumns, max(1, Int(availableWidth / (desired + 42))))
        let fittingRows = min(
            preferences.grid.rows,
            max(1, Int((availableHeight + Self.rowSpacing) / (desired + 38 + Self.rowSpacing))))
        if let compactItemCount {
            rows = min(fittingRows, max(1, (compactItemCount + columns - 1) / columns))
        } else {
            rows = fittingRows
        }
        cellWidth = availableWidth / CGFloat(columns)
        let fittedCellHeight =
            (availableHeight - CGFloat(rows - 1) * Self.rowSpacing) / CGFloat(rows)
        cellHeight =
            compactItemCount == nil ? fittedCellHeight : min(fittedCellHeight, desired + 38)
        contentWidth = availableWidth
        iconSize = min(desired, cellHeight - 32)
    }

    var capacity: Int { columns * rows }
}
