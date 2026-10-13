import Foundation
import LauncherCore
import Testing

@testable import LauncherInfrastructure

struct ApplicationScannerTests {
    @Test
    func standardRootsIncludeUserApplicationsUnderInjectedHome() {
        let home = URL(fileURLWithPath: "/tmp/example-home", isDirectory: true)
        let roots = ApplicationScanRoot.standardRoots(homeDirectory: home)

        #expect(
            roots.map(\.url.path) == [
                "/Applications",
                "/tmp/example-home/Applications",
                "/System/Applications",
                "/System/Cryptexes/App/System/Applications",
                "/System/Library/CoreServices/Applications",
            ])
    }

    @Test
    func scansNestedBundlesAndStopsAtApplicationBoundaries() async throws {
        let fixture = try ScanFixture()
        defer { fixture.remove() }
        let utilities = fixture.root.appending(path: "Utilities", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: utilities, withIntermediateDirectories: true)
        let main = try fixture.makeApplication(
            named: "Visible.app", in: utilities, displayName: "Visible App",
            identifier: "example.visible"
        )
        _ = try fixture.makeApplication(
            named: "Nested Helper.app",
            in: main.appending(path: "Contents/Library/LoginItems", directoryHint: .isDirectory),
            displayName: "Nested Helper",
            identifier: "example.visible.helper"
        )

        let result = try await ApplicationScanner().scan(roots: [fixture.scanRoot])

        let record = try #require(result.records.only)
        #expect(record.name == "Visible App")
        #expect(record.bundleIdentifier == "example.visible")
        #expect(record.url == main.resolvingSymlinksInPath().standardizedFileURL)
        #expect(result.roots.first?.completeness == .complete)
    }

    @Test
    func acceptsMenuBarAndWrapperBundles() async throws {
        let fixture = try ScanFixture()
        defer { fixture.remove() }
        _ = try fixture.makeApplication(
            named: "Menu Extra.app", displayName: "Menu Extra", identifier: "example.menu",
            extraInfo: ["LSUIElement": true]
        )
        _ = try fixture.makeApplication(
            named: "Website.app", displayName: "Website", identifier: "com.apple.Safari.WebApp",
            extraInfo: ["LSTemplateApplication": true]
        )
        _ = try fixture.makeApplication(
            named: "Tablet App.app", displayName: "Tablet App", identifier: "example.ios",
            extraInfo: ["LSRequiresIPhoneOS": true]
        )

        let result = try await ApplicationScanner().scan(roots: [fixture.scanRoot])

        #expect(Set(result.records.map(\.name)) == ["Menu Extra", "Website", "Tablet App"])
    }

    @Test
    func discoversInstalledIOSWrapperUsingOuterLaunchURL() async throws {
        let fixture = try ScanFixture()
        defer { fixture.remove() }
        let outer = try fixture.makeIOSWrapper(
            named: "Binance.app", displayName: "Binance", identifier: "com.binance.dev")

        let result = try await ApplicationScanner().scan(roots: [fixture.scanRoot])

        let record = try #require(result.records.only)
        #expect(record.name == "Binance")
        #expect(record.bundleIdentifier == "com.binance.dev")
        #expect(record.url == outer)
        #expect(result.roots.first?.completeness == .complete)
    }

    @Test
    func rejectsIOSWrappedBundleSymlinkThatEscapesOuterApplication() async throws {
        let fixture = try ScanFixture()
        let outside = try ScanFixture()
        defer { fixture.remove() }
        defer { outside.remove() }
        let outer = fixture.root.appending(path: "Escaped.app", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: outer, withIntermediateDirectories: true)
        let externalBundle = try outside.makeFlatIOSApplication(
            named: "Escaped.app", displayName: "Escaped", identifier: "example.escaped")
        try FileManager.default.createSymbolicLink(
            at: outer.appending(path: "WrappedBundle"), withDestinationURL: externalBundle)

        let result = try await ApplicationScanner().scan(roots: [fixture.scanRoot])

        #expect(result.records.isEmpty)
        #expect(result.roots.first?.completeness == .partial)
        #expect(result.roots.first?.issues.first?.kind == .invalidApplicationMetadata)
    }

    @Test
    func rejectsIOSWrapperDirectorySymlinkThatEscapesOuterApplication() async throws {
        let fixture = try ScanFixture()
        let outside = try ScanFixture()
        defer { fixture.remove() }
        defer { outside.remove() }
        let outer = fixture.root.appending(path: "Escaped.app", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: outer, withIntermediateDirectories: true)
        let externalBundle = try outside.makeFlatIOSApplication(
            named: "Escaped.app", displayName: "Escaped", identifier: "example.escaped")
        try FileManager.default.createSymbolicLink(
            at: outer.appending(path: "Wrapper", directoryHint: .isDirectory),
            withDestinationURL: outside.root)
        try FileManager.default.createSymbolicLink(
            at: outer.appending(path: "WrappedBundle"), withDestinationURL: externalBundle)

        let result = try await ApplicationScanner().scan(roots: [fixture.scanRoot])

        #expect(result.records.isEmpty)
        #expect(result.roots.first?.completeness == .partial)
        #expect(result.roots.first?.issues.first?.kind == .invalidApplicationMetadata)
    }

    @Test
    func malformedIOSWrapperIsReportedWithoutTraversingItsContents() async throws {
        let fixture = try ScanFixture()
        defer { fixture.remove() }
        let outer = fixture.root.appending(path: "Broken.app", directoryHint: .isDirectory)
        let inner = outer.appending(
            path: "Wrapper/Broken.app", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        try Data("invalid plist".utf8).write(to: inner.appending(path: "Info.plist"))
        try FileManager.default.createSymbolicLink(
            at: outer.appending(path: "WrappedBundle"), withDestinationURL: inner)

        let result = try await ApplicationScanner().scan(roots: [fixture.scanRoot])

        #expect(result.records.isEmpty)
        #expect(result.roots.first?.completeness == .partial)
        #expect(result.roots.first?.issues.count == 1)
    }

    @Test
    func resolvesSymlinkCyclesAndDeduplicatesCanonicalBundles() async throws {
        let fixture = try ScanFixture()
        defer { fixture.remove() }
        let app = try fixture.makeApplication(
            named: "Original.app", displayName: "Original", identifier: "example.original"
        )
        try FileManager.default.createSymbolicLink(
            at: fixture.root.appending(path: "Alias.app"), withDestinationURL: app
        )
        let nested = fixture.root.appending(path: "Nested", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: nested.appending(path: "Cycle", directoryHint: .isDirectory),
            withDestinationURL: fixture.root
        )

        let result = try await ApplicationScanner().scan(roots: [fixture.scanRoot])

        #expect(result.records.count == 1)
        #expect(result.records.first?.url == app.standardizedFileURL)
    }

    @Test
    func discoversCryptexApplicationAndDeduplicatesApplicationsAlias() async throws {
        let fixture = try ScanFixture()
        defer { fixture.remove() }
        let applications = fixture.root.appending(
            path: "Applications", directoryHint: .isDirectory)
        let cryptexApplications = fixture.root.appending(
            path: "System/Cryptexes/App/System/Applications", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: applications, withIntermediateDirectories: true)
        let safari = try fixture.makeApplication(
            named: "Safari.app", in: cryptexApplications, displayName: "Safari",
            identifier: "com.apple.Safari")
        try FileManager.default.createSymbolicLink(
            at: applications.appending(path: "Safari.app"), withDestinationURL: safari)
        let roots = [
            ApplicationScanRoot(id: "applications", url: applications, kind: .standard),
            ApplicationScanRoot(
                id: "cryptex", url: cryptexApplications, kind: .standard),
        ]

        let result = try await ApplicationScanner().scan(roots: roots)

        let record = try #require(result.records.only)
        #expect(record.name == "Safari")
        #expect(record.bundleIdentifier == "com.apple.Safari")
        #expect(record.url == safari)
        #expect(result.roots.allSatisfy { $0.completeness == .complete })
    }

    @Test
    func directorySymlinkCannotEscapeSelectedRoot() async throws {
        let fixture = try ScanFixture()
        let outside = try ScanFixture()
        defer { fixture.remove() }
        defer { outside.remove() }
        _ = try outside.makeApplication(
            named: "Private.app", displayName: "Private", identifier: "example.private")
        try FileManager.default.createSymbolicLink(
            at: fixture.root.appending(path: "Outside", directoryHint: .isDirectory),
            withDestinationURL: outside.root
        )

        let result = try await ApplicationScanner().scan(roots: [fixture.scanRoot])

        #expect(result.records.isEmpty)
        #expect(result.roots.first?.completeness == .complete)
    }

    @Test
    func unavailableCustomRootIsExplicitAndDoesNotProduceAnEmptySuccess() async throws {
        let fixture = try ScanFixture()
        defer { fixture.remove() }
        let unavailable = ApplicationScanRoot(
            id: "offline-volume",
            url: fixture.root.appending(path: "Unmounted"),
            kind: .custom
        )

        let result = try await ApplicationScanner().scan(roots: [unavailable])

        #expect(result.records.isEmpty)
        #expect(result.roots.first?.completeness == .unavailable)
        #expect(result.roots.first?.issues.first?.kind == .unavailable)
    }

    @Test
    func unreadableNestedDirectoryMakesRootPartial() async throws {
        let fixture = try ScanFixture()
        defer { fixture.remove() }
        let denied = fixture.root.appending(path: "Denied", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: denied, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: denied.path)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700], ofItemAtPath: denied.path)
        }

        let result = try await ApplicationScanner().scan(roots: [fixture.scanRoot])

        #expect(result.roots.first?.completeness == .partial)
        #expect(result.roots.first?.issues.first?.kind == .accessDenied)
    }

    @Test
    func malformedApplicationMetadataIsIgnored() async throws {
        let fixture = try ScanFixture()
        defer { fixture.remove() }
        let malformed = fixture.root.appending(
            path: "Broken.app/Contents", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: malformed, withIntermediateDirectories: true)
        try Data("not a plist".utf8).write(to: malformed.appending(path: "Info.plist"))

        let result = try await ApplicationScanner().scan(roots: [fixture.scanRoot])

        #expect(result.records.isEmpty)
        #expect(result.roots.first?.completeness == .partial)
        #expect(result.roots.first?.issues.first?.kind == .invalidApplicationMetadata)
    }

    @Test
    func cancelledScanThrowsCancellation() async throws {
        let fixture = try ScanFixture()
        defer { fixture.remove() }
        let root = fixture.scanRoot
        let task = Task { [root] in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await ApplicationScanner().scan(roots: [root])
        }

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }

    @Test
    func customRootTimeLimitProducesPartialResult() async throws {
        let fixture = try ScanFixture()
        defer { fixture.remove() }
        _ = try fixture.makeApplication(
            named: "App.app", displayName: "App", identifier: "example.app")

        let result = try await ApplicationScanner(customRootTimeLimit: .zero).scan(
            roots: [fixture.scanRoot])

        #expect(result.roots.first?.completeness == .partial)
        #expect(
            result.roots.first?.issues == [
                ApplicationScanIssue(kind: .timedOut, url: fixture.root)
            ])
    }

    @Test
    func entryLimitBoundsTraversal() async throws {
        let fixture = try ScanFixture()
        defer { fixture.remove() }
        _ = try fixture.makeApplication(
            named: "One.app", displayName: "One", identifier: "example.one")
        _ = try fixture.makeApplication(
            named: "Two.app", displayName: "Two", identifier: "example.two")

        let result = try await ApplicationScanner(maximumEntriesPerRoot: 1).scan(
            roots: [fixture.scanRoot])

        #expect(result.roots.first?.completeness == .partial)
        #expect(result.roots.first?.issues.first?.kind == .entryLimitReached)
        #expect(result.records.count <= 1)
    }
}

private final class ScanFixture {
    let root: URL

    var scanRoot: ApplicationScanRoot {
        ApplicationScanRoot(id: root.lastPathComponent, url: root, kind: .custom)
    }

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func makeApplication(
        named fileName: String,
        in directory: URL? = nil,
        displayName: String,
        identifier: String,
        extraInfo: [String: Any] = [:]
    ) throws -> URL {
        let application = (directory ?? root).appending(path: fileName, directoryHint: .isDirectory)
        let contents = application.appending(path: "Contents", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        var info: [String: Any] = [
            "CFBundleDisplayName": displayName,
            "CFBundleExecutable": "Fixture",
            "CFBundleIdentifier": identifier,
            "CFBundlePackageType": "APPL",
        ]
        info.merge(extraInfo) { _, new in new }
        let data = try PropertyListSerialization.data(
            fromPropertyList: info, format: .binary, options: 0
        )
        try data.write(to: contents.appending(path: "Info.plist"))
        return application.resolvingSymlinksInPath().standardizedFileURL
    }

    func makeIOSWrapper(
        named fileName: String,
        displayName: String,
        identifier: String
    ) throws -> URL {
        let outer = root.appending(path: fileName, directoryHint: .isDirectory)
        let inner = try makeFlatIOSApplication(
            named: fileName,
            in: outer.appending(path: "Wrapper", directoryHint: .isDirectory),
            displayName: displayName,
            identifier: identifier
        )
        try FileManager.default.createSymbolicLink(
            at: outer.appending(path: "WrappedBundle"), withDestinationURL: inner)
        return outer.standardizedFileURL
    }

    func makeFlatIOSApplication(
        named fileName: String,
        in directory: URL? = nil,
        displayName: String,
        identifier: String
    ) throws -> URL {
        let application = (directory ?? root).appending(path: fileName, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: application, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(
            fromPropertyList: [
                "CFBundleDisplayName": displayName,
                "CFBundleExecutable": "Fixture",
                "CFBundleIdentifier": identifier,
                "CFBundlePackageType": "APPL",
                "CFBundleSupportedPlatforms": ["iPhoneOS"],
                "LSRequiresIPhoneOS": true,
            ],
            format: .binary,
            options: 0
        )
        try data.write(to: application.appending(path: "Info.plist"))
        return application.standardizedFileURL
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

extension Collection {
    fileprivate var only: Element? { count == 1 ? first : nil }
}
