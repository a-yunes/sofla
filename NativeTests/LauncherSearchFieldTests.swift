import AppKit
import SwiftUI
import Testing

@testable import AppLauncher

@Suite
@MainActor
struct LauncherSearchFieldTests {
    @Test(arguments: ["", "Cal", "計算"])
    func arrowsNavigateWithoutMovingTheInsertionPoint(query: String) {
        var commands: [String] = []
        let coordinator = searchField(query: query) { commands.append($0) }.makeCoordinator()
        let editor = NSTextView()
        editor.string = query
        let insertionPoint = NSRange(location: query.utf16.count, length: 0)
        editor.setSelectedRange(insertionPoint)

        for selector in ["moveLeft:", "moveRight:", "moveUp:", "moveDown:"] {
            #expect(
                coordinator.control(
                    NSSearchField(), textView: editor, doCommandBy: NSSelectorFromString(selector)))
        }

        #expect(commands == ["horizontal:-1", "horizontal:1", "vertical:-1", "vertical:1"])
        #expect(editor.string == query)
        #expect(editor.selectedRange() == insertionPoint)
    }

    @Test
    func markedTextKeepsArrowCommandsInTheInputMethod() {
        var commands: [String] = []
        let coordinator = searchField(query: "") { commands.append($0) }.makeCoordinator()
        let editor = NSTextView()
        editor.setMarkedText(
            "か", selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(editor.hasMarkedText())

        for selector in ["moveLeft:", "moveRight:", "moveUp:", "moveDown:"] {
            #expect(
                !coordinator.control(
                    NSSearchField(), textView: editor, doCommandBy: NSSelectorFromString(selector)))
        }
        #expect(commands.isEmpty)
    }

    @Test
    func textEditingCommandsRemainAvailable() {
        var commands: [String] = []
        let coordinator = searchField(query: "Cal") { commands.append($0) }.makeCoordinator()

        for selector in [
            "moveWordLeft:", "moveWordRight:", "moveLeftAndModifySelection:",
            "moveRightAndModifySelection:", "deleteBackward:",
        ] {
            #expect(
                !coordinator.control(
                    NSSearchField(), textView: NSTextView(),
                    doCommandBy: NSSelectorFromString(selector)))
        }
        #expect(commands.isEmpty)
    }

    private func searchField(query: String, onCommand: @escaping (String) -> Void)
        -> LauncherSearchField
    {
        LauncherSearchField(
            text: .constant(query), focusGeneration: 0,
            submit: { onCommand("submit") }, escape: { onCommand("escape") },
            navigate: { onCommand("vertical:\($0)") },
            changePage: { onCommand("page:\($0)") },
            horizontal: { onCommand("horizontal:\($0)") }, didFocus: { _ in })
    }
}
