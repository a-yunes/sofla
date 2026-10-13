import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController {
    let setup: OnboardingModel
    private var window: NSWindow?

    init(setup: OnboardingModel) { self.setup = setup }

    func show(launcher: LauncherModel, completion: @escaping () -> Void) {
        setup.refresh()
        if let window {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 560),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Welcome to Sofla"
        window.identifier = NSUserInterfaceItemIdentifier("onboarding")
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(
            rootView: OnboardingView(
                setup: setup, launcher: launcher,
                finish: { [weak self] in
                    self?.window?.close()
                    self?.window = nil
                    completion()
                }))
        window.center()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}
