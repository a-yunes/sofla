import AppKit
import SwiftUI

struct LauncherSearchField: NSViewRepresentable {
    @Binding var text: String
    var focusGeneration: Int
    var submit: () -> Void
    var escape: () -> Void
    var navigate: (Int) -> Void
    var changePage: (Int) -> Void
    var horizontal: (Int) -> Void
    var didFocus: (Bool) -> Void
    var didUpdate: (String) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = "Search applications"
        field.identifier = NSUserInterfaceItemIdentifier("launcher.search")
        field.setAccessibilityIdentifier("launcher.search")
        field.setAccessibilityLabel("Search applications")
        field.font = .systemFont(ofSize: 15)
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        // Acknowledge the value applied to AppKit, even when result changes are coalesced.
        didUpdate(field.stringValue)
        if context.coordinator.focusGeneration != focusGeneration {
            let requestedGeneration = focusGeneration
            Task { @MainActor [weak field, weak coordinator = context.coordinator] in
                guard let field, let window = field.window, window.isVisible else { return }
                guard window.isKeyWindow else { return }
                guard let coordinator, coordinator.focusGeneration != requestedGeneration else {
                    return
                }
                coordinator.focusGeneration = requestedGeneration
                if window.makeFirstResponder(field), window.isVisible, window.isKeyWindow {
                    if let editor = field.currentEditor() as? NSTextView {
                        editor.setSelectedRange(
                            NSRange(location: field.stringValue.utf16.count, length: 0))
                    }
                    didFocus(true)
                }
            }
        }
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: LauncherSearchField
        var focusGeneration = -1

        init(_ parent: LauncherSearchField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector)
            -> Bool
        {
            guard !textView.hasMarkedText() else { return false }
            switch NSStringFromSelector(selector) {
            case "insertNewline:": parent.submit()
            case "cancelOperation:": parent.escape()
            case "moveLeft:": parent.horizontal(-1)
            case "moveRight:": parent.horizontal(1)
            case "moveDown:": parent.navigate(1)
            case "moveUp:": parent.navigate(-1)
            case "moveToBeginningOfLine:", "moveToLeftEndOfLine:":
                guard NSApp.currentEvent?.modifierFlags.contains(.command) == true else {
                    return false
                }
                parent.changePage(-1)
            case "moveToEndOfLine:", "moveToRightEndOfLine:":
                guard NSApp.currentEvent?.modifierFlags.contains(.command) == true else {
                    return false
                }
                parent.changePage(1)
            default: return false
            }
            return true
        }
    }
}
