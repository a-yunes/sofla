import AppKit
import LauncherCore

@MainActor
protocol DockIconTarget: AnyObject {
    var applicationIconImage: NSImage? { get set }
}

@MainActor
final class ApplicationDockIconTarget: DockIconTarget {
    var applicationIconImage: NSImage? {
        get { NSApp.applicationIconImage }
        set { NSApp.applicationIconImage = newValue }
    }
}

@MainActor
final class DockIconController {
    enum Error: Swift.Error, Equatable {
        case missingResource(String)
        case unreadableResource(String)
    }

    private let target: any DockIconTarget
    private let bundle: Bundle?
    private let imageLoader: (String) -> NSImage?

    init(
        target: any DockIconTarget = ApplicationDockIconTarget(),
        bundle: Bundle = .main,
        imageLoader: ((String) -> NSImage?)? = nil
    ) {
        self.target = target
        self.bundle = imageLoader == nil ? bundle : nil
        self.imageLoader =
            imageLoader ?? { name in
                guard let url = bundle.url(forResource: name, withExtension: "png") else {
                    return nil
                }
                return NSImage(contentsOf: url)
            }
    }

    func apply(_ appearance: LauncherPreferences.DockIconAppearance) throws {
        switch appearance {
        case .system:
            target.applicationIconImage = nil
        case .light:
            target.applicationIconImage = try image(named: "Floating-Light")
        case .dark:
            target.applicationIconImage = try image(named: "Floating-Dark")
        }
    }

    private func image(named name: String) throws -> NSImage {
        guard let image = imageLoader(name) else {
            throw bundle?.url(forResource: name, withExtension: "png") == nil
                ? Error.missingResource(name)
                : Error.unreadableResource(name)
        }
        return image
    }
}
