import AppKit
import Testing

@testable import AppLauncher

@MainActor
struct WallpaperServiceTests {
    @Test
    func unchangedFingerprintReusesImageWithoutRendering() async throws {
        let resource = WallpaperFixture()
        defer { Task { await resource.release() } }
        let service = makeService(resource)
        #expect(await service.prewarm(source: source) == .ready)
        let image = try #require(service.image)
        service.suspend()

        #expect(await service.prewarm(source: source) == .ready)

        #expect(service.image === image)
        #expect(await resource.renderCount == 1)
    }

    @Test
    func stablePathChangeMustRenderBeforeReadiness() async throws {
        let resource = WallpaperFixture()
        defer { Task { await resource.release() } }
        let service = makeService(resource)
        #expect(await service.prewarm(source: source) == .ready)
        let old = try #require(service.image)
        service.suspend()
        await resource.change(block: true)
        let preparation = Task { await service.prewarm(source: source) }
        try #require(await resource.started.wait(for: 2))
        #expect(service.state == .loading)
        #expect(service.image == nil)
        await resource.release()

        #expect(await preparation.value == .ready)
        #expect(service.image !== old)
        #expect(await resource.renderCount == 2)
    }

    @Test
    func cancelledPreparationRejectsLateRenderAndCanRetry() async throws {
        let resource = WallpaperFixture()
        defer { Task { await resource.release() } }
        await resource.change(block: true)
        let service = makeService(resource)
        let preparation = Task { await service.prewarm(source: source) }
        try #require(await resource.started.wait())
        preparation.cancel()
        #expect(await preparation.value == .idle)
        await resource.release()
        #expect(service.image == nil)
        #expect(await service.prewarm(source: source) == .ready)
    }

    @Test
    func unreadableChangedResourceCannotReuseStaleImage() async throws {
        let resource = WallpaperFixture()
        defer { Task { await resource.release() } }
        let service = makeService(resource)
        #expect(await service.prewarm(source: source) == .ready)
        service.suspend()
        await resource.fail()

        #expect(
            await service.prewarm(source: source) == .unavailable(.unreadableOrUnsupportedImage))
        #expect(service.image == nil)
    }

    private func makeService(_ fixture: WallpaperFixture) -> WallpaperService {
        WallpaperService(
            readFingerprint: { _ in try await fixture.fingerprint() },
            render: { _ in try await fixture.render() })
    }

    private var source: WallpaperSource {
        WallpaperSource(
            url: URL(fileURLWithPath: "/synthetic/wallpaper.png"), displayID: 1,
            pointWidth: 32, pointHeight: 32, backingScale: 1,
            scaling: .proportionallyUpOrDown, allowsClipping: true,
            fillColor: ColorComponents(red: 0, green: 0, blue: 0, alpha: 1))
    }
}

private actor WallpaperFixture {
    let started = TestSignal()
    private var version: UInt64 = 1
    private var blocked = false
    private var failed = false
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var renderCount = 0

    func change(block: Bool) {
        version += 1
        blocked = block
    }
    func fail() { failed = true }
    func fingerprint() throws -> WallpaperFileFingerprint {
        if failed { throw CocoaError(.fileReadUnknown) }
        return WallpaperFileFingerprint(
            deviceID: 1, fileID: version,
            modificationDate: Date(timeIntervalSince1970: Double(version)), byteCount: version)
    }
    func render() async throws -> CGImage {
        renderCount += 1
        if blocked {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                Task { await started.advance() }
            }
        } else {
            await started.advance()
        }
        if failed { throw CocoaError(.fileReadUnknown) }
        let context = try #require(
            CGContext(
                data: nil, width: 1, height: 1,
                bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        return try #require(context.makeImage())
    }
    func release() {
        blocked = false
        continuation?.resume()
        continuation = nil
    }
}
