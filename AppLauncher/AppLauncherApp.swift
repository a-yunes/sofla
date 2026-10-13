import AppKit
import LauncherCore

@main
@MainActor
enum AppLauncherApplication {
    static func main() {
        let application = NSApplication.shared
        do {
            let delegate = try AppDelegate(library: LibraryState())
            application.delegate = delegate
            application.setActivationPolicy(.regular)
            withExtendedLifetime(delegate) { application.run() }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Sofla could not start"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}
