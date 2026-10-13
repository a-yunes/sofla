import AppKit

extension AppDelegate {
    func configureMenus() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        appItem.title = "Sofla"
        let appMenu = NSMenu(title: "Sofla")
        appMenu.addItem(
            withTitle: "Show Launcher", action: #selector(showLauncher), keyEquivalent: "l"
        ).target = self
        appMenu.addItem(
            withTitle: "Settings…", action: #selector(showPreferences), keyEquivalent: ","
        ).target = self
        appMenu.addItem(
            withTitle: "Check for Updates…", action: #selector(UpdateService.checkForUpdates(_:)),
            keyEquivalent: ""
        ).target = model.updates
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Quit Sofla", action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: #selector(undo), keyEquivalent: "z").target = self
        let redoItem = edit.addItem(withTitle: "Redo", action: #selector(redo), keyEquivalent: "z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        redoItem.target = self
        edit.addItem(.separator())
        edit.addItem(
            withTitle: "Restore Alphabetical Order", action: #selector(restoreAlphabeticalOrder),
            keyEquivalent: ""
        ).target = self
        edit.addItem(.separator())
        for (name, selector, key) in [
            ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"),
            ("Select All", "selectAll:", "a"),
        ] {
            edit.addItem(withTitle: name, action: Selector(selector), keyEquivalent: key)
        }
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    @objc func undo() { model.undoManager.undo() }
    @objc func redo() { model.undoManager.redo() }
    @objc func restoreAlphabeticalOrder() { model.restoreAlphabeticalOrder() }
}
