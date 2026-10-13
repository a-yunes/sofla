import Foundation
import LauncherCore

public struct ApplicationScanRoot: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case standard
        case custom
    }

    public let id: String
    public let url: URL
    public let kind: Kind

    public init(id: String, url: URL, kind: Kind) {
        self.id = id
        self.url = url
        self.kind = kind
    }

    public static func standardRoots(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    )
        -> [Self]
    {
        [
            Self(id: "applications", url: URL(fileURLWithPath: "/Applications"), kind: .standard),
            Self(
                id: "user-applications",
                url: homeDirectory.appending(path: "Applications", directoryHint: .isDirectory),
                kind: .standard
            ),
            Self(
                id: "system-applications",
                url: URL(fileURLWithPath: "/System/Applications"),
                kind: .standard
            ),
            Self(
                id: "system-cryptex-applications",
                url: URL(fileURLWithPath: "/System/Cryptexes/App/System/Applications"),
                kind: .standard
            ),
            Self(
                id: "core-services-applications",
                url: URL(fileURLWithPath: "/System/Library/CoreServices/Applications"),
                kind: .standard
            ),
        ]
    }
}

public struct ApplicationScanIssue: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case unavailable
        case accessDenied
        case unreadableDirectory
        case invalidApplicationMetadata
        case timedOut
        case entryLimitReached
    }

    public let kind: Kind
    public let url: URL

    public init(kind: Kind, url: URL) {
        self.kind = kind
        self.url = url
    }
}

public struct ApplicationRootScanOutcome: Equatable, Sendable {
    public enum Completeness: String, Sendable {
        case complete
        case partial
        case unavailable
    }

    public let root: ApplicationScanRoot
    public let completeness: Completeness
    public let issues: [ApplicationScanIssue]
    public let canonicalRootURL: URL

    public init(
        root: ApplicationScanRoot,
        completeness: Completeness,
        issues: [ApplicationScanIssue],
        canonicalRootURL: URL? = nil
    ) {
        self.root = root
        self.completeness = completeness
        self.issues = issues
        self.canonicalRootURL = canonicalRootURL ?? root.url.standardizedFileURL
    }
}

public struct ApplicationScanResult: Equatable, Sendable {
    public let records: [ApplicationRecord]
    public let roots: [ApplicationRootScanOutcome]
    public let discoveryRootsByPath: [String: Set<String>]

    public init(
        records: [ApplicationRecord], roots: [ApplicationRootScanOutcome],
        discoveryRootsByPath: [String: Set<String>] = [:]
    ) {
        self.records = records
        self.roots = roots
        self.discoveryRootsByPath = discoveryRootsByPath
    }
}

public protocol ApplicationScanning: Sendable {
    func scan(roots: [ApplicationScanRoot]) async throws -> ApplicationScanResult
}

public actor ApplicationScanner: ApplicationScanning {
    private let customRootTimeLimit: Duration
    private let maximumEntriesPerRoot: Int
    private let clock = ContinuousClock()

    public init(
        customRootTimeLimit: Duration = .seconds(15),
        maximumEntriesPerRoot: Int = 100_000
    ) {
        self.customRootTimeLimit = max(customRootTimeLimit, .zero)
        self.maximumEntriesPerRoot = max(maximumEntriesPerRoot, 1)
    }

    public func scan(roots: [ApplicationScanRoot] = ApplicationScanRoot.standardRoots())
        async
        throws -> ApplicationScanResult
    {
        var recordsByCanonicalURL: [URL: ApplicationRecord] = [:]
        var outcomes: [ApplicationRootScanOutcome] = []
        var discoveryRootsByPath: [String: Set<String>] = [:]

        for root in roots {
            try Task.checkCancellation()
            let result = try scan(root: root)
            for record in result.records {
                recordsByCanonicalURL[record.url] = record
                discoveryRootsByPath[record.url.path, default: []].insert(
                    root.url.standardizedFileURL.path)
            }
            outcomes.append(result.outcome)
        }

        let records = recordsByCanonicalURL.values.sorted {
            if $0.name.localizedStandardCompare($1.name) == .orderedSame {
                return $0.url.path < $1.url.path
            }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        return ApplicationScanResult(
            records: records, roots: outcomes, discoveryRootsByPath: discoveryRootsByPath)
    }

    private func scan(root: ApplicationScanRoot) throws -> (
        records: [ApplicationRecord], outcome: ApplicationRootScanOutcome
    ) {
        let fileManager = FileManager.default
        let rootURL = canonicalURL(root.url)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: rootURL.path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else {
            return (
                [],
                ApplicationRootScanOutcome(
                    root: root,
                    completeness: .unavailable,
                    issues: [ApplicationScanIssue(kind: .unavailable, url: root.url)],
                    canonicalRootURL: rootURL
                )
            )
        }

        var pending = [rootURL]
        var visitedDirectories: Set<URL> = []
        var records: [ApplicationRecord] = []
        var issues: [ApplicationScanIssue] = []
        var visitedEntries = 0
        let deadline =
            root.kind == .custom ? clock.now.advanced(by: customRootTimeLimit) : nil

        scanDirectories: while let directory = pending.popLast() {
            try Task.checkCancellation()
            if let deadline, clock.now >= deadline {
                issues.append(ApplicationScanIssue(kind: .timedOut, url: root.url))
                break
            }
            let canonicalDirectory = canonicalURL(directory)
            guard visitedDirectories.insert(canonicalDirectory).inserted else { continue }

            let children: [URL]
            do {
                children = try fileManager.contentsOfDirectory(
                    at: canonicalDirectory,
                    includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                    options: [.skipsHiddenFiles]
                )
            } catch {
                let cocoaCode = (error as NSError).code
                let kind: ApplicationScanIssue.Kind =
                    cocoaCode == CocoaError.fileReadNoPermission.rawValue
                    ? .accessDenied : .unreadableDirectory
                issues.append(ApplicationScanIssue(kind: kind, url: directory))
                continue
            }

            for child in children {
                try Task.checkCancellation()
                visitedEntries += 1
                if visitedEntries > maximumEntriesPerRoot {
                    issues.append(
                        ApplicationScanIssue(kind: .entryLimitReached, url: directory))
                    break scanDirectories
                }
                if let deadline, clock.now >= deadline {
                    issues.append(ApplicationScanIssue(kind: .timedOut, url: root.url))
                    break scanDirectories
                }
                let canonicalChild = canonicalURL(child)
                if canonicalChild.pathExtension.localizedCaseInsensitiveCompare("app")
                    == .orderedSame
                {
                    switch ApplicationMetadataReader.applicationRecord(at: canonicalChild) {
                    case .record(let record):
                        records.append(record)
                    case .notApplication: break
                    case .invalidMetadata:
                        issues.append(
                            ApplicationScanIssue(
                                kind: .invalidApplicationMetadata, url: canonicalChild))
                    }
                    continue
                }

                do {
                    let values = try canonicalChild.resourceValues(forKeys: [.isDirectoryKey])
                    if values.isDirectory == true,
                        canonicalChild.pathComponents.starts(with: rootURL.pathComponents)
                    {
                        pending.append(canonicalChild)
                    }
                } catch {
                    issues.append(
                        ApplicationScanIssue(kind: .unreadableDirectory, url: canonicalChild))
                }
            }
        }

        let rootWasUnreadable = issues.contains {
            ($0.kind == .accessDenied || $0.kind == .unreadableDirectory)
                && canonicalURL($0.url) == rootURL
        }
        return (
            records,
            ApplicationRootScanOutcome(
                root: root,
                completeness: rootWasUnreadable
                    ? .unavailable : (issues.isEmpty ? .complete : .partial),
                issues: issues, canonicalRootURL: rootURL
            )
        )
    }

    private func canonicalURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }
}
