import Foundation
import Testing

@testable import AppLauncher

struct WallpaperFileFingerprintTests {
    @Test
    func unchangedFileHasStableFingerprint() async throws {
        let fixture = try WallpaperFileFixture(contents: Data("wallpaper".utf8))
        defer { fixture.remove() }

        let first = try await WallpaperFileFingerprint.read(from: fixture.url)
        let second = try await WallpaperFileFingerprint.read(from: fixture.url)

        #expect(first == second)
    }

    @Test
    func atomicReplacementAtSameURLChangesFingerprint() async throws {
        let fixture = try WallpaperFileFixture(contents: Data("first-data".utf8))
        defer { fixture.remove() }
        let before = try await WallpaperFileFingerprint.read(from: fixture.url)

        try Data("other-data".utf8).write(to: fixture.url, options: .atomic)
        let after = try await WallpaperFileFingerprint.read(from: fixture.url)

        #expect(after != before)
        #expect(after.byteCount == before.byteCount)
        #expect(after.fileID != before.fileID || after.modificationDate != before.modificationDate)
    }

    @Test
    func inPlaceSizeChangeChangesFingerprint() async throws {
        let fixture = try WallpaperFileFixture(contents: Data("small".utf8))
        defer { fixture.remove() }
        let before = try await WallpaperFileFingerprint.read(from: fixture.url)

        try Data(repeating: 7, count: 128).write(to: fixture.url)
        let after = try await WallpaperFileFingerprint.read(from: fixture.url)

        #expect(after != before)
        #expect(after.byteCount == 128)
    }
}

private final class WallpaperFileFixture {
    let directory: URL
    let url: URL

    init(contents: Data) throws {
        directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        url = directory.appending(path: "wallpaper.heic")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try contents.write(to: url)
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
