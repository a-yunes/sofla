import AppKit
import LauncherCore
import Testing

@testable import AppLauncher

@Suite
@MainActor
struct DockIconControllerTests {
    @Test
    func systemAppearanceReturnsControlToTheCompiledIcon() throws {
        let target = TestDockIconTarget()
        target.applicationIconImage = NSImage(size: NSSize(width: 20, height: 20))
        let controller = DockIconController(target: target)

        try controller.apply(.system)

        #expect(target.applicationIconImage == nil)
    }

    @Test
    func lightAndDarkAppearanceUseTheNamedRuntimeArtwork() throws {
        let target = TestDockIconTarget()
        let applicationAppearance = NSApp.appearance
        var requestedNames: [String] = []
        let controller = DockIconController(target: target) { name in
            requestedNames.append(name)
            return NSImage(size: NSSize(width: 1024, height: 1024))
        }

        try controller.apply(.light)
        #expect(target.applicationIconImage?.size == NSSize(width: 1024, height: 1024))
        try controller.apply(.dark)
        #expect(target.applicationIconImage?.size == NSSize(width: 1024, height: 1024))
        #expect(requestedNames == ["Floating-Light", "Floating-Dark"])
        #expect(NSApp.appearance === applicationAppearance)
    }

    @Test
    func missingArtworkDoesNotReplaceTheExistingIcon() {
        let target = TestDockIconTarget()
        let existing = NSImage(size: NSSize(width: 20, height: 20))
        target.applicationIconImage = existing
        let controller = DockIconController(target: target, imageLoader: { _ in nil })

        #expect(throws: DockIconController.Error.missingResource("Floating-Light")) {
            try controller.apply(.light)
        }
        #expect(target.applicationIconImage === existing)
    }
}

@MainActor
private final class TestDockIconTarget: DockIconTarget {
    var applicationIconImage: NSImage?
}
