import Foundation

nonisolated protocol ApplicationVolumeInspecting: Sendable {
    func isReadOnlyVolume(at url: URL) throws -> Bool
}

nonisolated struct URLApplicationVolumeInspector: ApplicationVolumeInspecting {
    func isReadOnlyVolume(at url: URL) throws -> Bool {
        try url.resourceValues(forKeys: [.volumeIsReadOnlyKey]).volumeIsReadOnly == true
    }
}

nonisolated struct ApplicationTrashEligibility {
    enum Failure: Equatable, Sendable {
        case notLocalApplication
        case runningApplication
        case protectedSystemRoot
        case missingTarget
        case readOnlyVolume
        case volumeStatusUnavailable
        case parentNotWritable
        case targetNotWritable
    }

    static func failure(
        for url: URL,
        appLauncherURL: URL,
        fileManager: FileManager = .default,
        volumeInspector: any ApplicationVolumeInspecting = URLApplicationVolumeInspector()
    ) -> Failure? {
        guard url.isFileURL, url.pathExtension.lowercased() == "app" else {
            return .notLocalApplication
        }

        let resolvedURL = url.standardizedFileURL.resolvingSymlinksInPath()
        let resolvedLauncherURL = appLauncherURL.standardizedFileURL.resolvingSymlinksInPath()
        guard resolvedURL != resolvedLauncherURL else { return .runningApplication }

        let protectedRoots = [
            "/System", "/usr", "/bin", "/sbin",
        ]
        let path = resolvedURL.path
        guard
            !protectedRoots.contains(where: { root in
                path == root || path.hasPrefix(root + "/")
            })
        else { return .protectedSystemRoot }

        guard fileManager.fileExists(atPath: resolvedURL.path) else {
            return .missingTarget
        }
        let parentURL = resolvedURL.deletingLastPathComponent()
        guard fileManager.fileExists(atPath: parentURL.path),
            fileManager.isWritableFile(atPath: parentURL.path)
        else { return .parentNotWritable }

        guard fileManager.isWritableFile(atPath: resolvedURL.path) else {
            return .targetNotWritable
        }

        let isReadOnlyVolume: Bool
        do {
            isReadOnlyVolume = try volumeInspector.isReadOnlyVolume(at: resolvedURL)
        } catch {
            return .volumeStatusUnavailable
        }
        if isReadOnlyVolume {
            return .readOnlyVolume
        }
        return nil
    }

    static func isEligible(
        _ url: URL,
        appLauncherURL: URL,
        fileManager: FileManager = .default,
        volumeInspector: any ApplicationVolumeInspecting = URLApplicationVolumeInspector()
    ) -> Bool {
        failure(
            for: url,
            appLauncherURL: appLauncherURL,
            fileManager: fileManager,
            volumeInspector: volumeInspector
        ) == nil
    }

    @concurrent
    static func evaluate(_ url: URL, appLauncherURL: URL) async -> Bool {
        isEligible(url, appLauncherURL: appLauncherURL)
    }
}
