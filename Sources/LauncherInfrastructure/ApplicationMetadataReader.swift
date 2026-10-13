import Foundation
import LauncherCore

enum ApplicationMetadataResult {
    case record(ApplicationRecord)
    case notApplication
    case invalidMetadata
}

enum ApplicationMetadataReader {
    private static let maximumMetadataBytes = 1_024 * 1_024

    static func applicationRecord(at outerURL: URL) -> ApplicationMetadataResult {
        guard let metadata = applicationMetadata(at: outerURL) else { return .invalidMetadata }
        let info = metadata.info
        let packageType = info["CFBundlePackageType"] as? String
        guard packageType == nil || packageType == "APPL" else { return .notApplication }

        let bundle = Bundle(url: metadata.bundleURL)
        let localizedName =
            bundle?.localizedInfoDictionary?["CFBundleDisplayName"] as? String
            ?? bundle?.localizedInfoDictionary?["CFBundleName"] as? String
            ?? info["CFBundleDisplayName"] as? String
            ?? info["CFBundleName"] as? String
        let fallbackName = outerURL.deletingPathExtension().lastPathComponent
        let name = localizedName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = name.flatMap { $0.isEmpty ? nil : $0 } ?? fallbackName

        let record = ApplicationRecord(
            id: "url:\(outerURL.absoluteString)",
            name: resolvedName,
            bundleIdentifier: info["CFBundleIdentifier"] as? String,
            url: outerURL
        )
        guard (try? CatalogCacheValidator.validate(record)) != nil else {
            return .invalidMetadata
        }
        return .record(record)
    }

    private static func applicationMetadata(at outerURL: URL) -> (
        info: [String: Any], bundleURL: URL
    )? {
        let conventionalInfoURL = outerURL.appending(path: "Contents/Info.plist")
        if FileManager.default.fileExists(atPath: conventionalInfoURL.path) {
            return readInfo(at: conventionalInfoURL).map { ($0, outerURL) }
        }

        let wrappedBundleLink = outerURL.appending(path: "WrappedBundle")
        guard
            (try? wrappedBundleLink.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink
                == true
        else { return nil }
        let wrappedBundle = canonicalURL(wrappedBundleLink)
        let canonicalOuter = canonicalURL(outerURL)
        let expectedWrapperDirectory = canonicalOuter.appending(
            path: "Wrapper", directoryHint: .isDirectory)
        let wrapperDirectory = canonicalURL(
            outerURL.appending(path: "Wrapper", directoryHint: .isDirectory))
        guard
            wrapperDirectory == expectedWrapperDirectory,
            wrappedBundle.pathExtension.localizedCaseInsensitiveCompare("app") == .orderedSame,
            wrappedBundle.deletingLastPathComponent() == wrapperDirectory,
            let info = readInfo(at: wrappedBundle.appending(path: "Info.plist")),
            isIOSApplication(info)
        else { return nil }
        return (info, wrappedBundle)
    }

    private static func readInfo(at url: URL) -> [String: Any]? {
        guard
            let data = try? readMetadata(at: url),
            let info = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil
            ) as? [String: Any]
        else { return nil }
        return info
    }

    private static func isIOSApplication(_ info: [String: Any]) -> Bool {
        guard info["CFBundlePackageType"] as? String == "APPL" else { return false }
        if info["LSRequiresIPhoneOS"] as? Bool == true { return true }
        if info["UIDeviceFamily"] != nil { return true }
        return (info["CFBundleSupportedPlatforms"] as? [String])?.contains("iPhoneOS") == true
    }

    private static func canonicalURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    private static func readMetadata(at url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumMetadataBytes + 1) ?? Data()
        guard data.count <= maximumMetadataBytes else {
            throw CocoaError(.fileReadTooLarge)
        }
        return data
    }
}
