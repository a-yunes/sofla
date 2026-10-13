import AppKit
import Observation

#if canImport(Sparkle)
    import Sparkle
#endif

@MainActor @Observable
final class UpdateService: NSObject {
    private(set) var automaticChecks = false
    private(set) var automaticDownloads = false
    private(set) var canCheck = false
    private(set) var lastChecked: Date?
    private(set) var error: String?
    @ObservationIgnored var onWillPresent: (() -> Void)?
    @ObservationIgnored private let isTesting: Bool
    @ObservationIgnored private var started = false
    #if canImport(Sparkle)
        @ObservationIgnored private var controller: SPUStandardUpdaterController?
        @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    #endif

    init(isTesting: Bool) {
        self.isTesting = isTesting
        super.init()
        canCheck = isTesting
    }

    func start() {
        guard !started, !isTesting else { return }
        #if canImport(Sparkle)
            let controller = SPUStandardUpdaterController(
                startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
            self.controller = controller
            do {
                try controller.updater.start()
                started = true
                let updater = controller.updater
                observations = [
                    updater.observe(\.canCheckForUpdates, options: [.initial, .new]) {
                        [weak self] _, _ in
                        Task { @MainActor in self?.refresh() }
                    },
                    updater.observe(\.automaticallyChecksForUpdates, options: [.new]) {
                        [weak self] _, _ in
                        Task { @MainActor in self?.refresh() }
                    },
                    updater.observe(\.automaticallyDownloadsUpdates, options: [.new]) {
                        [weak self] _, _ in
                        Task { @MainActor in self?.refresh() }
                    },
                    updater.observe(\.lastUpdateCheckDate, options: [.new]) { [weak self] _, _ in
                        Task { @MainActor in self?.refresh() }
                    },
                ]
                refresh()
            } catch {
                self.error = "Updates could not start. \(error.localizedDescription)"
            }
        #endif
    }

    func setAutomaticChecks(_ enabled: Bool) {
        automaticChecks = enabled
        #if canImport(Sparkle)
            controller?.updater.automaticallyChecksForUpdates = enabled
        #endif
    }

    func setAutomaticDownloads(_ enabled: Bool) {
        automaticDownloads = enabled
        #if canImport(Sparkle)
            controller?.updater.automaticallyDownloadsUpdates = enabled
        #endif
    }

    @objc func checkForUpdates(_ sender: Any?) {
        guard canCheck else { return }
        if isTesting {
            lastChecked = Date()
            return
        }
        onWillPresent?()
        #if canImport(Sparkle)
            controller?.checkForUpdates(sender)
        #endif
    }

    private func refresh() {
        #if canImport(Sparkle)
            guard let updater = controller?.updater else { return }
            automaticChecks = updater.automaticallyChecksForUpdates
            automaticDownloads = updater.automaticallyDownloadsUpdates
            canCheck = updater.canCheckForUpdates
            lastChecked = updater.lastUpdateCheckDate
        #endif
    }
}

extension UpdateService: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool { canCheck }
}

#if canImport(Sparkle)
    extension UpdateService: SPUUpdaterDelegate {
        func allowedSystemProfileKeys(for updater: SPUUpdater) -> [String]? { [] }
    }

    extension UpdateService: SPUStandardUserDriverDelegate {
        func standardUserDriverWillShowModalAlert() { onWillPresent?() }

        func standardUserDriverWillHandleShowingUpdate(
            _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
        ) {
            if handleShowingUpdate { onWillPresent?() }
        }
    }
#endif
