import Foundation

public enum GridPaginator {
    public static func pageCount(itemCount: Int, capacity: Int) -> Int {
        guard itemCount > 0, capacity > 0 else { return 0 }
        return ((itemCount - 1) / capacity) + 1
    }

    public static func items<Element>(onPage page: Int, from items: [Element], capacity: Int)
        -> ArraySlice<Element>
    {
        guard capacity > 0, page >= 0 else { return items[0..<0] }
        guard items.isEmpty || page <= (items.count - 1) / capacity else { return items[0..<0] }
        let lower = min(page * capacity, items.count)
        let upper = min(lower + capacity, items.count)
        return items[lower..<upper]
    }

    public static func clampedPage(_ page: Int, itemCount: Int, capacity: Int) -> Int {
        max(0, min(page, max(0, pageCount(itemCount: itemCount, capacity: capacity) - 1)))
    }
}

public enum GridMove: Sendable {
    case left
    case right
    case up
    case down
    case previousPage
    case nextPage
}

public enum GridNavigation {
    public static func destination(
        from selectedIndex: Int?, move: GridMove, itemCount: Int, columns: Int, rows: Int
    ) -> Int? {
        guard itemCount > 0, columns > 0, rows > 0, columns <= Int.max / rows else { return nil }
        let current = min(max(selectedIndex ?? 0, 0), itemCount - 1)
        let capacity = columns * rows
        let pageStart = (current / capacity) * capacity
        let pageEnd = min(pageStart + capacity, itemCount) - 1
        switch move {
        case .left: return max(pageStart, current - 1)
        case .right: return min(pageEnd, current + 1)
        case .up: return max(pageStart, current - columns)
        case .down: return min(pageEnd, current + columns)
        case .previousPage: return max(0, current - capacity)
        case .nextPage: return min(itemCount - 1, current + capacity)
        }
    }

    public static func selectionAfterRemoval(
        previousIndex: Int?, itemCount: Int
    ) -> Int? {
        guard itemCount > 0 else { return nil }
        return min(max(previousIndex ?? 0, 0), itemCount - 1)
    }
}
