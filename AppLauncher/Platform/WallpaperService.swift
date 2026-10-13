import AppKit
import Observation

/// Produces a bounded, blurred snapshot of the current display's public desktop image.
@MainActor
@Observable
public final class WallpaperService: NSObject {
    public enum UnavailableReason: Sendable, Equatable {
        case noDesktopImage
        case unreadableOrUnsupportedImage
    }

    public enum State: Sendable, Equatable {
        case idle
        case loading
        case ready
        case unavailable(UnavailableReason)
    }

    private enum WaitOutcome {
        case terminal
        case timedOut
        case cancelled
    }

    public private(set) var image: NSImage?
    public private(set) var state: State = .idle {
        didSet {
            guard state != .loading else { return }
            let pending = stateWaiters.values
            stateWaiters.removeAll()
            for waiter in pending { waiter.resume(returning: .terminal) }
        }
    }

    @ObservationIgnored private var renderTask: Task<Void, Never>?
    @ObservationIgnored private var sourceMonitorTask: Task<Void, Never>?
    @ObservationIgnored private var cachedSource: WallpaperSource?
    @ObservationIgnored private var cachedFingerprint: WallpaperFileFingerprint?
    @ObservationIgnored private var requestedDisplayID: CGDirectDisplayID?
    @ObservationIgnored private var isVisible = false
    @ObservationIgnored private var preparationGeneration: UInt64 = 0
    @ObservationIgnored private var stateWaiters: [UUID: CheckedContinuation<WaitOutcome, Never>] =
        [:]

    @ObservationIgnored private let readFingerprint:
        @Sendable (URL) async throws -> WallpaperFileFingerprint
    @ObservationIgnored private let render: @Sendable (WallpaperSource) async throws -> CGImage

    public override init() {
        readFingerprint = WallpaperFileFingerprint.read
        render = WallpaperRenderer.render
        super.init()
        observeSourceChanges()
    }

    init(
        readFingerprint: @escaping @Sendable (URL) async throws -> WallpaperFileFingerprint,
        render: @escaping @Sendable (WallpaperSource) async throws -> CGImage
    ) {
        self.readFingerprint = readFingerprint
        self.render = render
        super.init()
    }

    private func observeSourceChanges() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceCenter.addObserver(
            self,
            selector: #selector(sourceDidChange(_:)),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
        workspaceCenter.addObserver(
            self,
            selector: #selector(sourceDidChange(_:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sourceDidChange(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    isolated deinit {
        renderTask?.cancel()
        sourceMonitorTask?.cancel()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }

    /// Starts or reuses preparation for a visible launcher on `screen`.
    public func prepare(for screen: NSScreen) {
        startPreparation(source: Self.source(for: screen), visible: true)
    }

    @discardableResult
    private func startPreparation(source: WallpaperSource?, visible: Bool) -> UInt64 {
        preparationGeneration &+= 1
        let generation = preparationGeneration
        isVisible = visible
        if visible {
            startSourceMonitoringIfNeeded()
        } else {
            sourceMonitorTask?.cancel()
            sourceMonitorTask = nil
        }
        guard let source else {
            clear(with: .noDesktopImage)
            return generation
        }
        requestedDisplayID = source.displayID
        let canReuseImage = cachedSource == source && image != nil

        renderTask?.cancel()
        cachedSource = source
        state = .loading

        let readFingerprint = readFingerprint
        let render = render
        renderTask = Task(priority: .userInitiated) { [weak self] in
            do {
                let fingerprintBeforeRender = try? await readFingerprint(source.url)
                try Task.checkCancellation()
                guard let self, self.preparationGeneration == generation else { return }
                if canReuseImage, let fingerprintBeforeRender,
                    fingerprintBeforeRender == self.cachedFingerprint
                {
                    self.state = .ready
                    return
                }
                self.image = nil
                let cgImage = try await render(source)
                let fingerprintAfterRender = try? await readFingerprint(source.url)
                try Task.checkCancellation()
                guard self.preparationGeneration == generation,
                    self.cachedSource == source
                else { return }

                self.cachedFingerprint =
                    fingerprintBeforeRender == fingerprintAfterRender
                    ? fingerprintAfterRender : fingerprintBeforeRender
                self.image = NSImage(
                    cgImage: cgImage,
                    size: NSSize(width: source.pointWidth, height: source.pointHeight)
                )
                self.state = .ready
            } catch is CancellationError {
                return
            } catch {
                guard let self, self.preparationGeneration == generation,
                    self.cachedSource == source
                else { return }
                self.image = nil
                self.state = .unavailable(.unreadableOrUnsupportedImage)
            }
        }
        return generation
    }

    public func prewarm(for screen: NSScreen, timeout: Duration = .seconds(3)) async -> State {
        await prewarm(source: Self.source(for: screen), timeout: timeout)
    }

    func prewarm(source: WallpaperSource?, timeout: Duration = .seconds(3)) async -> State {
        let generation = startPreparation(source: source, visible: false)
        let outcome = await waitUntilTerminal(timeout: timeout)
        if outcome == .timedOut, generation == preparationGeneration {
            renderTask?.cancel()
            renderTask = nil
            image = nil
            state = .unavailable(.unreadableOrUnsupportedImage)
        } else if outcome == .cancelled, generation == preparationGeneration {
            renderTask?.cancel()
            renderTask = nil
            image = nil
            state = .idle
        }
        guard generation == preparationGeneration else { return .idle }
        isVisible = false
        sourceMonitorTask?.cancel()
        sourceMonitorTask = nil
        return state
    }

    private func waitUntilTerminal(timeout: Duration) async -> WaitOutcome {
        if state != .loading { return .terminal }
        let id = UUID()
        let timeoutTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: timeout)
                self?.resumeWaiter(id: id, outcome: .timedOut)
            } catch {
                self?.resumeWaiter(id: id, outcome: .cancelled)
            }
        }
        let result: WaitOutcome = await withTaskCancellationHandler {
            await withCheckedContinuation {
                (continuation: CheckedContinuation<WaitOutcome, Never>) in
                if state != .loading || Task.isCancelled {
                    continuation.resume(
                        returning: Task.isCancelled
                            ? WaitOutcome.cancelled : WaitOutcome.terminal)
                } else {
                    stateWaiters[id] = continuation
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.resumeWaiter(id: id, outcome: .cancelled)
            }
        }
        timeoutTask.cancel()
        return result
    }

    private func resumeWaiter(id: UUID, outcome: WaitOutcome) {
        guard let waiter = stateWaiters.removeValue(forKey: id) else { return }
        waiter.resume(returning: outcome)
    }

    public func activatePrepared() {
        isVisible = true
        startSourceMonitoringIfNeeded()
    }

    /// Stops pending work while retaining the single warm image for the next invocation.
    public func suspend() {
        preparationGeneration &+= 1
        isVisible = false
        renderTask?.cancel()
        sourceMonitorTask?.cancel()
        renderTask = nil
        sourceMonitorTask = nil
        if image != nil {
            state = .ready
        } else if case .unavailable = state {
            // Preserve the terminal fallback so the next presentation stays visually stable.
        } else {
            state = .idle
        }
    }

    public func cancel() {
        suspend()
        cachedSource = nil
        cachedFingerprint = nil
        requestedDisplayID = nil
        image = nil
        state = .idle
    }

    @objc private func sourceDidChange(_ notification: Notification) {
        preparationGeneration &+= 1
        renderTask?.cancel()
        renderTask = nil
        cachedSource = nil
        cachedFingerprint = nil
        image = nil

        guard isVisible, let requestedDisplayID else {
            state = .idle
            return
        }
        guard
            let screen = NSScreen.screens.first(where: {
                Self.displayID(for: $0) == requestedDisplayID
            })
        else {
            clear(with: .noDesktopImage)
            return
        }
        prepare(for: screen)
    }

    private func startSourceMonitoringIfNeeded() {
        guard sourceMonitorTask == nil else { return }
        sourceMonitorTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(5))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                await self?.refreshVisibleSourceIfNeeded()
            }
        }
    }

    private func refreshVisibleSourceIfNeeded() async {
        guard isVisible, let requestedDisplayID else { return }
        guard
            let screen = NSScreen.screens.first(where: {
                Self.displayID(for: $0) == requestedDisplayID
            }),
            let source = Self.source(for: screen, displayID: requestedDisplayID)
        else {
            if image != nil || state != .unavailable(.noDesktopImage) {
                clear(with: .noDesktopImage)
            }
            return
        }
        guard source == cachedSource else {
            prepare(for: screen)
            return
        }
        guard let fingerprint = try? await readFingerprint(source.url) else {
            return
        }
        guard !Task.isCancelled, isVisible, source == cachedSource else { return }
        guard fingerprint != cachedFingerprint else { return }
        cachedSource = nil
        cachedFingerprint = nil
        prepare(for: screen)
    }

    private func clear(with reason: UnavailableReason) {
        renderTask?.cancel()
        renderTask = nil
        cachedSource = nil
        cachedFingerprint = nil
        image = nil
        state = .unavailable(reason)
    }

    private static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
            .map { CGDirectDisplayID($0.uint32Value) }
    }

    private static func source(for screen: NSScreen) -> WallpaperSource? {
        guard let displayID = displayID(for: screen) else { return nil }
        return source(for: screen, displayID: displayID)
    }

    private static func source(for screen: NSScreen, displayID: CGDirectDisplayID)
        -> WallpaperSource?
    {
        let workspace = NSWorkspace.shared
        guard let url = workspace.desktopImageURL(for: screen), url.isFileURL else { return nil }
        let options = workspace.desktopImageOptions(for: screen) ?? [:]
        let scalingValue = (options[.imageScaling] as? NSNumber)?.uintValue
        let scaling =
            scalingValue.flatMap(NSImageScaling.init(rawValue:))
            ?? .scaleProportionallyUpOrDown
        let allowsClipping = (options[.allowClipping] as? NSNumber)?.boolValue ?? true
        let fillColor =
            (options[.fillColor] as? NSColor)
            .flatMap { $0.usingColorSpace(.sRGB) }
            .map(ColorComponents.init)
            ?? ColorComponents(red: 0, green: 0, blue: 0, alpha: 1)
        let pointSize = screen.frame.size
        let backingScale = max(1, screen.backingScaleFactor)

        return WallpaperSource(
            url: url,
            displayID: displayID,
            pointWidth: pointSize.width,
            pointHeight: pointSize.height,
            backingScale: backingScale,
            scaling: WallpaperScaling(scaling),
            allowsClipping: allowsClipping,
            fillColor: fillColor
        )
    }
}

struct ColorComponents: Sendable, Equatable {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    let alpha: CGFloat

    init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    @MainActor
    init(_ color: NSColor) {
        red = color.redComponent
        green = color.greenComponent
        blue = color.blueComponent
        alpha = color.alphaComponent
    }
}

enum WallpaperScaling: Sendable, Equatable {
    case axesIndependently
    case proportionallyDown
    case proportionallyUpOrDown
    case none

    init(_ scaling: NSImageScaling) {
        switch scaling {
        case .scaleAxesIndependently:
            self = .axesIndependently
        case .scaleProportionallyDown:
            self = .proportionallyDown
        case .scaleProportionallyUpOrDown:
            self = .proportionallyUpOrDown
        case .scaleNone:
            self = .none
        @unknown default:
            self = .proportionallyUpOrDown
        }
    }
}

struct WallpaperSource: Sendable, Equatable {
    let url: URL
    let displayID: CGDirectDisplayID
    let pointWidth: CGFloat
    let pointHeight: CGFloat
    let backingScale: CGFloat
    let scaling: WallpaperScaling
    let allowsClipping: Bool
    let fillColor: ColorComponents
}
