import Foundation
import Testing

@testable import AppLauncher

@Suite
@MainActor
struct ApplicationTrashEligibilityTests {
    @Test
    func writableLocalAppIsEligible() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppLauncherTrashEligibility-\(UUID().uuidString)")
        let app = root.appendingPathComponent("Example.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(
            ApplicationTrashEligibility.failure(
                for: app, appLauncherURL: root.appendingPathComponent("Sofla.app")) == nil)
    }

    @Test
    func nonAppAndProtectedTargetsAreRejected() {
        let launcher = URL(fileURLWithPath: "/Applications/Sofla.app")

        #expect(
            ApplicationTrashEligibility.failure(
                for: URL(fileURLWithPath: "/private/tmp/notes.txt"), appLauncherURL: launcher)
                == .notLocalApplication)
        #expect(
            ApplicationTrashEligibility.failure(
                for: URL(fileURLWithPath: "/System/Applications/Calculator.app"),
                appLauncherURL: launcher) == .protectedSystemRoot)
    }

    @Test
    func runningAppIsRejectedBeforeFilesystemChecks() {
        let launcher = URL(fileURLWithPath: "/private/tmp/Sofla.app")

        #expect(
            ApplicationTrashEligibility.failure(for: launcher, appLauncherURL: launcher)
                == .runningApplication)
    }

    @Test
    func readOnlyApplicationBundleIsRejected() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppLauncherReadOnlyTrash-\(UUID().uuidString)")
        let app = root.appendingPathComponent("Example.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: app.path)
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: app.path)

        #expect(
            ApplicationTrashEligibility.failure(
                for: app, appLauncherURL: root.appendingPathComponent("Sofla.app"))
                == .targetNotWritable)
    }

    @Test
    func unavailableVolumeStatusFailsClosed() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppLauncherVolumeStatus-\(UUID().uuidString)")
        let app = root.appendingPathComponent("Example.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(
            ApplicationTrashEligibility.failure(
                for: app,
                appLauncherURL: root.appendingPathComponent("Sofla.app"),
                volumeInspector: ThrowingVolumeInspector()
            ) == .volumeStatusUnavailable)
    }
}

nonisolated private struct ThrowingVolumeInspector: ApplicationVolumeInspecting {
    func isReadOnlyVolume(at url: URL) throws -> Bool {
        throw CocoaError(.fileReadUnknown)
    }
}
