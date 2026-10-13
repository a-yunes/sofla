import Testing

@testable import LauncherCore

struct GridNavigationTests {
    @Test
    func paginatesPartialLastPage() {
        #expect(GridPaginator.pageCount(itemCount: 36, capacity: 35) == 2)
        #expect(Array(GridPaginator.items(onPage: 1, from: Array(0..<36), capacity: 35)) == [35])
        #expect(GridPaginator.clampedPage(8, itemCount: 36, capacity: 35) == 1)
        #expect(GridPaginator.pageCount(itemCount: 0, capacity: 35) == 0)
        #expect(GridPaginator.pageCount(itemCount: Int.max, capacity: Int.max) == 1)
        #expect(GridPaginator.items(onPage: Int.max, from: [1], capacity: 1).isEmpty)
    }

    @Test
    func arrowsStayWithinCurrentPageAndIncompleteRows() {
        #expect(
            GridNavigation.destination(from: 34, move: .right, itemCount: 38, columns: 7, rows: 5)
                == 34)
        #expect(
            GridNavigation.destination(
                from: 34, move: .nextPage, itemCount: 38, columns: 7, rows: 5) == 37)
        #expect(
            GridNavigation.destination(from: 37, move: .down, itemCount: 38, columns: 7, rows: 5)
                == 37)
        #expect(
            GridNavigation.destination(
                from: 37, move: .previousPage, itemCount: 38, columns: 7, rows: 5) == 2)
        #expect(
            GridNavigation.destination(
                from: 0, move: .right, itemCount: 1, columns: Int.max, rows: 2) == nil)
    }

    @Test
    func selectionClampsAfterFilteringOrRemoval() {
        #expect(GridNavigation.selectionAfterRemoval(previousIndex: 5, itemCount: 3) == 2)
        #expect(GridNavigation.selectionAfterRemoval(previousIndex: 0, itemCount: 0) == nil)
    }
}
