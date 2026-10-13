import AppKit

@MainActor
enum LauncherDialogs {
    static func text(
        title: String, detail: String, initial: String, accept: String = "Save",
        completion: @escaping (String) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: accept)
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(string: initial)
        field.frame = NSRect(x: 0, y: 0, width: 340, height: 28)
        field.setAccessibilityIdentifier("dialog.text")
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        present(alert) { response in
            if response == .alertFirstButtonReturn { completion(field.stringValue) }
        }
    }

    static func confirm(
        title: String, detail: String, accept: String, completion: @escaping () -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: accept)
        alert.addButton(withTitle: "Cancel")
        present(alert) { if $0 == .alertFirstButtonReturn { completion() } }
    }

    static func present(
        _ alert: NSAlert, completion: @escaping (NSApplication.ModalResponse) -> Void
    ) {
        if let window = NSApp.keyWindow {
            alert.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(alert.runModal())
        }
    }
}
