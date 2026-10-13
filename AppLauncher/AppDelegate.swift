import AppKit
import Carbon.HIToolbox
import LauncherCore
import Sparkle
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private enum PreferencesPresentation {
        case none
        case standalone
        case overlay
    }

    let model: LauncherModel
    private let onboarding: OnboardingWindowController
    private let usesOnboarding: Bool
    private let shortcut = GlobalShortcut()
    private let shortcutOverride: GlobalShortcut.Shortcut?
    private let dockIconController = DockIconController()
    private var panel: LauncherPanel?
    private var preferencesWindow: NSWindow?
    private var previousApplication: NSRunningApplication?
    private var observers: [NSObjectProtocol] = []
    private var isShowingPreferences = false
    private var preferencesPresentation: PreferencesPresentation = .none
    private var pendingLauncherGeneration: Int?
    private var focusedLauncherGeneration: Int?
    private var launcherGeneration = 0
    private var pendingPreferencesPresentation = false
    private var preferencesFocusTask: Task<Void, Never>?
    private var modelStartTask: Task<Void, Never>?
    private var launcherReadinessTask: Task<Void, Never>?
    private var launcherReadinessGeneration = 0

    init(library: LibraryState) throws {
        let arguments = ProcessInfo.processInfo.arguments
        let isTesting =
            !arguments.contains("--live-verification")
            && (arguments.contains("--ui-testing")
                || ProcessInfo.processInfo.environment["APP_LAUNCHER_TESTING"] == "1")
        let directory: URL
        if let index = arguments.firstIndex(of: "--state-directory"),
            arguments.indices.contains(index + 1)
        {
            directory = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        } else if isTesting {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                "app-launcher-ui-\(UUID().uuidString)")
        } else {
            directory = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil,
                create: false
            )
            .appendingPathComponent("Sofla", isDirectory: true)
        }
        shortcutOverride = Self.testShortcutOverride(arguments: arguments)
        model = LauncherModel(library: library, dataDirectory: directory, isTesting: isTesting)
        usesOnboarding = !isTesting || arguments.contains("--onboarding-testing")
        onboarding = OnboardingWindowController(
            setup: OnboardingModel(
                login: model.login,
                completionURL: directory.appendingPathComponent("setup-complete")))
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let outputURL = Self.iconBenchmarkOutputURL(
            arguments: ProcessInfo.processInfo.arguments)
        {
            Task { @MainActor in
                do {
                    let result = try await ApplicationIconBenchmark.run(outputURL: outputURL)
                    print(
                        String(
                            format:
                                "icon_benchmark_one_ms=%.3f two_ms=%.3f three_ms=%.3f production_improvement=%.1f%%",
                            result.oneWorkerMedianMilliseconds,
                            result.twoWorkerMedianMilliseconds,
                            result.threeWorkerMedianMilliseconds,
                            result.improvementPercent
                        ))
                } catch {
                    print("icon_benchmark_error=\(error)")
                }
                NSApp.terminate(nil)
            }
            return
        }
        configureMenus()
        model.updates.onWillPresent = { [weak self] in
            self?.hideLauncher(restoreFocus: false)
        }
        model.onDismiss = { [weak self] restore in self?.hideLauncher(restoreFocus: restore) }
        model.onPreferences = { [weak self] in self?.showPreferences() }
        model.onPreferencesChanged = { [weak self] in try self?.configurePreferences() }
        observeWorkspace()
        let event = NSAppleEventManager.shared().currentAppleEvent
        let properties = event?.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))
        let loginLaunch =
            properties?.forKeyword(AEKeyword(keyAELaunchedAsLogInItem)) != nil
            || ((model.isTesting
                || ProcessInfo.processInfo.arguments.contains("--benchmark-invocation"))
                && ProcessInfo.processInfo.arguments.contains("--simulate-login-launch"))
        modelStartTask = Task { @MainActor [weak self] in
            defer { self?.modelStartTask = nil }
            guard let self else { return }
            await model.start()
            if let outputURL = Self.invocationBenchmarkOutputURL(
                arguments: ProcessInfo.processInfo.arguments)
            {
                if loginLaunch, let screen = await screenForPrewarming() {
                    model.prepareToShow()
                    model.fit(displayGrid(for: screen))
                    await model.prewarmForLogin(on: screen)
                }
                showLauncher()
                await launcherReadinessTask?.value
                await runInvocationBenchmark(outputURL: outputURL)
                if !model.isTesting
                    || !ProcessInfo.processInfo.arguments.contains("--benchmark-keep-running")
                {
                    NSApp.terminate(nil)
                }
                return
            }
            if usesOnboarding, !onboarding.setup.isComplete {
                showOnboarding()
                return
            }
            if loginLaunch {
                if let screen = await screenForPrewarming() {
                    model.prepareToShow()
                    model.fit(displayGrid(for: screen))
                    await model.prewarmForLogin(on: screen)
                }
            } else {
                showLauncher()
                await launcherReadinessTask?.value
            }
            model.updates.start()
            if !model.isTesting, !model.recoveryLocked, shortcut.registeredShortcut == nil {
                showPreferences()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool)
        -> Bool
    {
        showLauncher()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationDidBecomeActive(_ notification: Notification) {
        model.login.refresh()
        if pendingLauncherGeneration != nil {
            completeLauncherPresentation()
        }
        if pendingPreferencesPresentation {
            completePreferencesPresentation()
        } else if isShowingPreferences, preferencesPresentation == .overlay {
            panel?.orderFront(nil)
            preferencesWindow?.makeKeyAndOrderFront(nil)
        }
    }

    func applicationDidResignActive(_ notification: Notification) {
        let hasLauncherPresentation =
            pendingLauncherGeneration != nil || focusedLauncherGeneration != nil
            || panel?.isVisible == true
        guard hasLauncherPresentation,
            panel?.attachedSheet == nil, NSApp.modalWindow == nil
        else { return }
        hideLauncher()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === panel,
            let generation = pendingLauncherGeneration
        else { return }
        pendingLauncherGeneration = nil
        focusedLauncherGeneration = generation
        model.focusGeneration += 1
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === preferencesWindow else {
            return
        }
        let wasOverlay = preferencesPresentation == .overlay
        detachPreferencesWindow()
        pendingPreferencesPresentation = false
        isShowingPreferences = false
        preferencesPresentation = .none
        guard wasOverlay, NSApp.isActive, let panel else { return }
        preferencesFocusTask?.cancel()
        modelStartTask?.cancel()
        launcherReadinessTask?.cancel()
        preferencesFocusTask = Task { @MainActor [weak self, weak panel] in
            defer { self?.preferencesFocusTask = nil }
            await Task.yield()
            guard !Task.isCancelled, let self, NSApp.isActive,
                preferencesPresentation == .none
            else { return }
            panel?.makeKeyAndOrderFront(nil)
            model.focusGeneration += 1
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if ProcessInfo.processInfo.arguments.contains("--benchmark-icons")
            || ProcessInfo.processInfo.arguments.contains("--benchmark-invocation")
        {
            return .terminateNow
        }
        Task { @MainActor in
            if await model.flush() {
                sender.reply(toApplicationShouldTerminate: true)
            } else {
                let alert = NSAlert()
                alert.messageText = "Quit without saving?"
                alert.informativeText =
                    "The latest changes could not be saved. Your last saved layout is preserved."
                alert.addButton(withTitle: "Quit")
                alert.addButton(withTitle: "Cancel")
                LauncherDialogs.present(alert) {
                    sender.reply(toApplicationShouldTerminate: $0 == .alertFirstButtonReturn)
                }
            }
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.changes.stop()
        model.scanTask?.cancel()
        model.scanRequestTask?.cancel()
        model.dropConfirmationTask?.cancel()
        model.recycleTask?.cancel()
        model.trashEligibilityTask?.cancel()
        preferencesFocusTask?.cancel()
        model.stopDragPaging()
        model.wallpaper.cancel()
        shortcut.unregister()
        for token in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
            NotificationCenter.default.removeObserver(token)
        }
    }

    @objc func toggleLauncher() {
        if panel?.isVisible == true { hideLauncher(restoreFocus: true) } else { showLauncher() }
    }

    private func showOnboarding() {
        onboarding.show(launcher: model) { [weak self] in
            self?.showLauncher()
            Task { @MainActor [weak self] in
                await self?.launcherReadinessTask?.value
                self?.model.updates.start()
            }
        }
    }

    @objc func showLauncher() {
        if usesOnboarding, !onboarding.setup.isComplete {
            showOnboarding()
            return
        }
        guard !reuseVisiblePresentation() else { return }
        launcherReadinessGeneration &+= 1
        let generation = launcherReadinessGeneration
        launcherReadinessTask?.cancel()
        launcherReadinessTask = Task { @MainActor [weak self] in
            defer {
                if self?.launcherReadinessGeneration == generation {
                    self?.launcherReadinessTask = nil
                }
            }
            await self?.requestLauncherPresentation(generation: generation)
        }
    }

    private func reuseVisiblePresentation() -> Bool {
        if let preferencesWindow, preferencesWindow.isVisible {
            guard preferencesWindow.attachedSheet == nil, NSApp.modalWindow == nil else {
                return true
            }
            guard !NSApp.isActive || !preferencesWindow.isKeyWindow else { return true }
            NSApp.activate()
            if preferencesPresentation == .overlay { panel?.orderFrontRegardless() }
            preferencesWindow.makeKeyAndOrderFront(nil)
            return true
        }
        guard let panel, panel.isVisible, model.isPresentationReady else { return false }
        guard panel.attachedSheet == nil, NSApp.modalWindow == nil else { return true }
        guard !NSApp.isActive || !panel.isKeyWindow else { return true }
        panel.orderFrontRegardless()
        NSApp.activate()
        if NSApp.isActive { panel.makeKeyAndOrderFront(nil) }
        return true
    }

    private func requestLauncherPresentation(generation: Int) async {
        model.isPresentationReady = false
        model.performance.beginInvocation()
        if !model.isReady {
            await modelStartTask?.value
        }
        guard !Task.isCancelled, model.isReady, generation == launcherReadinessGeneration else {
            return
        }
        let pointer = NSEvent.mouseLocation
        guard
            let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) })
                ?? NSScreen.main
        else { return }
        if NSWorkspace.shared.frontmostApplication?.processIdentifier
            != ProcessInfo.processInfo.processIdentifier
        {
            previousApplication = NSWorkspace.shared.frontmostApplication
        }
        model.prepareToShow()
        ensurePanel(on: screen)
        panel?.contentView?.layoutSubtreeIfNeeded()
        await Task.yield()
        panel?.contentView?.layoutSubtreeIfNeeded()
        var readiness: LauncherModel.PresentationReadiness = .stale
        for attempt in 0..<3 where readiness == .stale {
            if attempt > 0 { await Task.yield() }
            guard !Task.isCancelled, generation == launcherReadinessGeneration else { return }
            readiness = await model.prepareForPresentation(on: screen)
        }
        if model.performance.enabled {
            print("launcher_readiness=\(readiness)")
        }
        guard !Task.isCancelled, generation == launcherReadinessGeneration,
            readiness == .ready || readiness == .fallback
        else {
            panel?.orderOut(nil)
            return
        }
        model.isPresentationReady = true
        presentPreparedLauncher(on: screen)
    }

    private func ensurePanel(on screen: NSScreen) {
        if panel == nil {
            let window = LauncherPanel(
                contentRect: screen.frame, styleMask: [.borderless],
                backing: .buffered, defer: false)
            window.identifier = NSUserInterfaceItemIdentifier("launcher")
            window.title = "Sofla"
            window.level = .floating
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.hidesOnDeactivate = true
            window.delegate = self
            window.collectionBehavior = [
                .canJoinAllSpaces, .fullScreenAuxiliary, .canJoinAllApplications, .ignoresCycle,
            ]
            window.contentView = NSHostingView(rootView: LauncherView(model: model))
            window.updateScrollThreshold(
                CGFloat(model.preferences.pageSwipeSensitivity.scrollThreshold))
            window.onEscape = { [weak model] in model?.escape() }
            window.onHorizontalNavigation = { [weak model] in
                model?.navigate($0 < 0 ? .left : .right)
            }
            window.onPageScroll = { [weak model] delta in
                guard let model else { return false }
                model.changePage(delta)
                return true
            }
            window.allowsPageScroll = { [weak model] in
                guard let model else { return false }
                return model.query.isEmpty
            }
            panel = window
        }
        panel?.setFrame(screen.frame, display: false)
        model.fit(displayGrid(for: screen))
        panel?.alphaValue = 0
        panel?.ignoresMouseEvents = true
    }

    private func displayGrid(for screen: NSScreen) -> DisplayGrid {
        DisplayGrid(
            size: CGSize(
                width: max(100, screen.frame.width - 90),
                height: max(120, screen.frame.height - 276)
            ),
            preferences: model.preferences
        )
    }

    private func presentPreparedLauncher(on screen: NSScreen) {
        if isShowingPreferences {
            detachPreferencesWindow()
            preferencesWindow?.orderOut(nil)
            pendingPreferencesPresentation = false
            isShowingPreferences = false
            preferencesPresentation = .none
        }
        launcherGeneration += 1
        pendingLauncherGeneration = launcherGeneration
        focusedLauncherGeneration = nil
        pendingPreferencesPresentation = false
        isShowingPreferences = false
        ensurePanel(on: screen)
        panel?.setFrame(screen.frame, display: false)
        panel?.alphaValue = 1
        panel?.ignoresMouseEvents = false
        // Invocation can arrive while another app is active. Raise the overlay immediately;
        // activation callbacks still own keyboard focus and deactivation still dismisses it.
        panel?.orderFrontRegardless()
        NSApp.activate()
        if NSApp.isActive { completeLauncherPresentation() }
        model.activatePreparedPresentation()
    }

    func hideLauncher(restoreFocus: Bool = false) {
        launcherReadinessTask?.cancel()
        pendingLauncherGeneration = nil
        focusedLauncherGeneration = nil
        panel?.orderOut(nil)
        model.wallpaper.suspend()
        model.stopDragPaging()
        model.draggedItem = nil
        model.isPresentationReady = false
        if restoreFocus, let previousApplication, !previousApplication.isTerminated {
            NSApp.yieldActivation(to: previousApplication)
            previousApplication.activate()
        }
    }

    @objc func showPreferences() {
        let wasPreparingLauncher = launcherReadinessTask != nil
        launcherReadinessGeneration &+= 1
        launcherReadinessTask?.cancel()
        launcherReadinessTask = nil
        if wasPreparingLauncher { model.isPresentationReady = false }
        preferencesFocusTask?.cancel()
        preferencesFocusTask = nil
        let retainsLauncher =
            pendingLauncherGeneration != nil || focusedLauncherGeneration != nil
            || panel?.isVisible == true
        isShowingPreferences = true
        if !retainsLauncher {
            pendingLauncherGeneration = nil
            focusedLauncherGeneration = nil
            model.wallpaper.suspend()
        }
        if preferencesWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
                styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered,
                defer: false)
            window.title = "Sofla Settings"
            window.identifier = NSUserInterfaceItemIdentifier("preferences")
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 700, height: 500)
            window.delegate = self
            window.contentView = NSHostingView(rootView: PreferencesView(model: model))
            window.center()
            preferencesWindow = window
        }

        if retainsLauncher, let panel, let preferencesWindow {
            if preferencesWindow.parent !== panel {
                panel.addChildWindow(preferencesWindow, ordered: .above)
            }
            preferencesPresentation = .overlay
        } else {
            detachPreferencesWindow()
            preferencesPresentation = .standalone
        }
        pendingPreferencesPresentation = true
        NSApp.activate()
        if NSApp.isActive { completePreferencesPresentation() }
        model.login.refresh()
    }

    private func screenForPrewarming() async -> NSScreen? {
        for attempt in 0..<10 {
            if let screen = NSScreen.main ?? NSScreen.screens.first { return screen }
            if attempt < 9 {
                do {
                    try await Task.sleep(for: .milliseconds(100))
                } catch {
                    return nil
                }
            }
        }
        return nil
    }

    private func detachPreferencesWindow() {
        guard let preferencesWindow, let parent = preferencesWindow.parent else { return }
        parent.removeChildWindow(preferencesWindow)
    }

    private func completeLauncherPresentation() {
        guard pendingLauncherGeneration != nil, NSApp.isActive, let panel else { return }
        panel.makeKeyAndOrderFront(nil)
        if panel.isKeyWindow, let generation = pendingLauncherGeneration {
            pendingLauncherGeneration = nil
            focusedLauncherGeneration = generation
            model.focusGeneration += 1
        }
    }

    private func completePreferencesPresentation() {
        guard pendingPreferencesPresentation, NSApp.isActive, let preferencesWindow else {
            return
        }
        pendingPreferencesPresentation = false
        preferencesWindow.makeKeyAndOrderFront(nil)
    }

    func configurePreferences() throws {
        if !model.isTesting {
            let value =
                shortcutOverride
                ?? GlobalShortcut.Shortcut(
                    keyCode: model.preferences.shortcut.keyCode,
                    modifiers: .init(rawValue: model.preferences.shortcut.modifiers)
                )
            try shortcut.register(
                value
            ) { [weak self] in
                self?.toggleLauncher()
            }
        }
        try dockIconController.apply(model.preferences.dockIconAppearance)
        panel?.updateScrollThreshold(
            CGFloat(model.preferences.pageSwipeSensitivity.scrollThreshold))
    }

    private static func testShortcutOverride(arguments: [String]) -> GlobalShortcut.Shortcut? {
        guard arguments.contains("--ui-testing") || arguments.contains("--live-verification"),
            let keyIndex = arguments.firstIndex(of: "--test-shortcut-key-code"),
            arguments.indices.contains(keyIndex + 1),
            let keyCode = UInt32(arguments[keyIndex + 1]),
            let modifiersIndex = arguments.firstIndex(of: "--test-shortcut-modifiers"),
            arguments.indices.contains(modifiersIndex + 1),
            let modifiers = UInt32(arguments[modifiersIndex + 1])
        else { return nil }
        return GlobalShortcut.Shortcut(
            keyCode: keyCode,
            modifiers: .init(rawValue: modifiers)
        )
    }

    private static func iconBenchmarkOutputURL(arguments: [String]) -> URL? {
        guard arguments.contains("--benchmark-icons"),
            let index = arguments.firstIndex(of: "--benchmark-output"),
            arguments.indices.contains(index + 1)
        else { return nil }
        return URL(fileURLWithPath: arguments[index + 1])
    }

    private static func invocationBenchmarkOutputURL(arguments: [String]) -> URL? {
        guard arguments.contains("--benchmark-invocation"),
            let index = arguments.firstIndex(of: "--benchmark-output"),
            arguments.indices.contains(index + 1)
        else { return nil }
        return URL(fileURLWithPath: arguments[index + 1])
    }

    private func runInvocationBenchmark(outputURL: URL) async {
        guard await waitForInvocationSamples(1) else {
            print("invocation_benchmark_error=initial focus timed out")
            return
        }
        for count in 2...21 {
            hideLauncher()
            showLauncher()
            guard await waitForInvocationSamples(count) else {
                print("invocation_benchmark_error=warm focus timed out at sample \(count)")
                return
            }
        }
        let searchQueries = ["Sample 0050", "Sample 00", "Sample", "No Matching Application", ""]
        for index in 0..<100 {
            let query = searchQueries[index % searchQueries.count]
            model.performance.beginSearchUpdate(query: query)
            model.query = query
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while model.performance.searchUpdateSamples.count <= index,
                ContinuousClock.now < deadline
            {
                try? await Task.sleep(for: .milliseconds(2))
            }
            guard model.performance.searchUpdateSamples.count == index + 1 else {
                print("invocation_benchmark_error=search view update timed out at sample \(index)")
                print(
                    "benchmark_state active=\(NSApp.isActive) visible=\(panel?.isVisible == true) key=\(panel?.isKeyWindow == true) ready=\(model.isPresentationReady) query_matches=\(model.query == query) samples=\(model.performance.searchUpdateSamples.count)"
                )
                return
            }
        }
        let samples = model.performance.millisecondSamples
        let warm = Array(samples.dropFirst())
        let sorted = warm.sorted()
        let result = LauncherInvocationBenchmarkResult(
            coldMilliseconds: samples[0],
            warmSamplesMilliseconds: warm,
            warmP50Milliseconds: Self.percentile(0.50, sorted: sorted),
            warmP95Milliseconds: Self.percentile(0.95, sorted: sorted),
            searchRecordCount: model.library.records.count,
            searchUpdateSamplesMilliseconds: model.performance.searchUpdateSamples
        )
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(result).write(to: outputURL, options: .atomic)
            print(
                String(
                    format: "invocation_benchmark_cold_ms=%.3f warm_p50_ms=%.3f warm_p95_ms=%.3f",
                    result.coldMilliseconds,
                    result.warmP50Milliseconds,
                    result.warmP95Milliseconds
                ))
        } catch {
            print("invocation_benchmark_error=\(error)")
        }
    }

    private func waitForInvocationSamples(_ count: Int) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        while model.performance.millisecondSamples.count < count,
            ContinuousClock.now < deadline
        {
            try? await Task.sleep(for: .milliseconds(2))
        }
        return model.performance.millisecondSamples.count >= count
    }

    private static func percentile(_ percentile: Double, sorted samples: [Double]) -> Double {
        let index = max(0, Int(ceil(percentile * Double(samples.count))) - 1)
        return samples[min(index, samples.count - 1)]
    }

    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(
            center.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
            ) { [weak self] note in
                guard
                    let app = note.userInfo?[NSWorkspace.applicationUserInfoKey]
                        as? NSRunningApplication
                else { return }
                let url = app.bundleURL
                let pid = app.processIdentifier
                Task { @MainActor [weak self] in
                    guard let self, pid != ProcessInfo.processInfo.processIdentifier else { return }
                    if let url,
                        let record = model.library.records.first(where: {
                            $0.url.standardizedFileURL == url.standardizedFileURL
                        })
                    {
                        model.recordActivation(record.id, source: .workspace)
                    }
                }
            })
        for name in [
            NSWorkspace.didWakeNotification, NSWorkspace.didMountNotification,
            NSWorkspace.didUnmountNotification,
        ] {
            observers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.model.refreshCatalog() }
                })
        }
    }

}
