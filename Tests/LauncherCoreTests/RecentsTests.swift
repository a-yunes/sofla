import Foundation
import Testing

@testable import LauncherCore

struct RecentsTests {
    private let now = Date(timeIntervalSince1970: 2_000_000)

    @Test
    func maximumCountSupportsPreferenceBoundsAndRejectsOutsideValues() throws {
        #expect(
            try RecentsPolicy(maximumCount: LauncherPreferences.maximumRecentsCountRange.lowerBound)
                .maximumCount == 1)
        #expect(
            try RecentsPolicy(maximumCount: LauncherPreferences.maximumRecentsCountRange.upperBound)
                .maximumCount == 200)
        #expect(throws: RecentsError.invalidMaximumCount) {
            try RecentsPolicy(maximumCount: 0)
        }
        #expect(throws: RecentsError.invalidMaximumCount) {
            try RecentsPolicy(maximumCount: RecentsPolicy.maximumHistoryLimit + 1)
        }
    }

    @Test
    func recordsMostRecentOnceAndFiltersInvalidEvents() throws {
        let policy = try RecentsPolicy(retentionDays: 30, maximumCount: 2)
        var history = [
            RecentApplication(applicationID: "a", accessedAt: now.addingTimeInterval(-100))
        ]
        history = policy.recording(
            applicationID: "a", at: now, source: .workspace, history: history,
            catalogIDs: ["a", "b"], hiddenIDs: [])
        history = policy.recording(
            applicationID: "b", at: now.addingTimeInterval(1), source: .workspace, history: history,
            catalogIDs: ["a", "b"], hiddenIDs: [])
        #expect(history.map(\.applicationID) == ["b", "a"])
        #expect(
            policy.recording(
                applicationID: "x", at: now.addingTimeInterval(2), source: .workspace,
                history: history,
                catalogIDs: ["a", "b"], hiddenIDs: []) == history)
    }

    @Test
    func disabledAndLauncherScopeDoNotResurrectOrRecordWorkspaceEvents() throws {
        let disabled = try RecentsPolicy(recordsEvents: false)
        let old = [RecentApplication(applicationID: "a", accessedAt: now)]
        #expect(
            disabled.recording(
                applicationID: "b", at: now, source: .launcher, history: old,
                catalogIDs: ["a", "b"], hiddenIDs: []
            ).map(\.applicationID) == ["a"])

        let launcherOnly = try RecentsPolicy(scope: .launcher)
        #expect(
            launcherOnly.recording(
                applicationID: "b", at: now, source: .workspace, history: old,
                catalogIDs: ["a", "b"], hiddenIDs: []
            ).map(\.applicationID) == ["a"])
        #expect(
            launcherOnly.recording(
                applicationID: "b", at: now, source: .launcher, history: old,
                catalogIDs: ["a", "b"], hiddenIDs: []
            ).map(\.applicationID) == ["b", "a"])
    }

    @Test
    func retentionHiddenRemovalFutureDatesAndLimitAreEnforced() throws {
        let policy = try RecentsPolicy(retentionDays: 1, maximumCount: 1)
        let history = [
            RecentApplication(applicationID: "old", accessedAt: now.addingTimeInterval(-172_800)),
            RecentApplication(applicationID: "hidden", accessedAt: now),
            RecentApplication(applicationID: "future", accessedAt: now.addingTimeInterval(1)),
            RecentApplication(applicationID: "a", accessedAt: now.addingTimeInterval(-1)),
            RecentApplication(applicationID: "b", accessedAt: now.addingTimeInterval(-2)),
        ]
        #expect(
            policy.pruned(
                history, now: now, catalogIDs: ["a", "b", "hidden", "future", "old"],
                hiddenIDs: ["hidden"]
            ).map(\.applicationID) == ["a"])
    }

    @Test
    func loweringMaximumCountPrunesExistingHistoryImmediately() throws {
        let history = [
            RecentApplication(applicationID: "a", accessedAt: now),
            RecentApplication(applicationID: "b", accessedAt: now.addingTimeInterval(-1)),
            RecentApplication(applicationID: "c", accessedAt: now.addingTimeInterval(-2)),
        ]
        let lowered = try RecentsPolicy(maximumCount: 1)

        #expect(
            lowered.pruned(history, now: now, catalogIDs: ["a", "b", "c"], hiddenIDs: [])
                .map(\.applicationID) == ["a"])
    }

    @Test
    func groupsUsingInjectedCalendarAcrossOffsetBoundary() throws {
        let policy = try RecentsPolicy()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: -10 * 3_600)!
        let history = [
            RecentApplication(applicationID: "a", accessedAt: Date(timeIntervalSince1970: 86_400)),
            RecentApplication(
                applicationID: "b", accessedAt: Date(timeIntervalSince1970: 86_400 + 43_200)),
        ]
        #expect(policy.grouped(history, calendar: calendar).count == 2)
    }
}
