import Foundation

public struct RecentApplication: Codable, Equatable, Sendable {
    public let applicationID: String
    public let accessedAt: Date

    public init(applicationID: String, accessedAt: Date) {
        self.applicationID = applicationID
        self.accessedAt = accessedAt
    }
}

public enum ActivationSource: Equatable, Sendable {
    case launcher
    case workspace
}

public struct RecentsPolicy: Equatable, Sendable {
    public static let maximumHistoryLimit = 10_000

    public var retentionDays: Int
    public var maximumCount: Int
    public var recordsEvents: Bool
    public var scope: LauncherPreferences.RecentsScope

    public init(
        retentionDays: Int = 30,
        maximumCount: Int = 500,
        recordsEvents: Bool = true,
        scope: LauncherPreferences.RecentsScope = .anywhere
    ) throws {
        guard LauncherPreferences.retentionDaysRange.contains(retentionDays) else {
            throw RecentsError.invalidRetentionDays
        }
        guard (1...Self.maximumHistoryLimit).contains(maximumCount) else {
            throw RecentsError.invalidMaximumCount
        }
        self.retentionDays = retentionDays
        self.maximumCount = maximumCount
        self.recordsEvents = recordsEvents
        self.scope = scope
    }

    public func recording(
        applicationID: String,
        at date: Date,
        source: ActivationSource,
        history: [RecentApplication],
        catalogIDs: Set<String>,
        hiddenIDs: Set<String>
    ) -> [RecentApplication] {
        guard recordsEvents,
            catalogIDs.contains(applicationID),
            !hiddenIDs.contains(applicationID),
            scope == .anywhere || source == .launcher
        else { return pruned(history, now: date, catalogIDs: catalogIDs, hiddenIDs: hiddenIDs) }

        let withoutDuplicate = history.filter { $0.applicationID != applicationID }
        return pruned(
            [RecentApplication(applicationID: applicationID, accessedAt: date)] + withoutDuplicate,
            now: date,
            catalogIDs: catalogIDs,
            hiddenIDs: hiddenIDs
        )
    }

    public func pruned(
        _ history: [RecentApplication],
        now: Date,
        catalogIDs: Set<String>,
        hiddenIDs: Set<String>
    ) -> [RecentApplication] {
        let cutoff =
            Calendar(identifier: .gregorian).date(
                byAdding: .day, value: -retentionDays, to: now) ?? now
        var seen = Set<String>()
        return Array(
            history
                .filter {
                    $0.accessedAt >= cutoff && $0.accessedAt <= now
                        && catalogIDs.contains($0.applicationID)
                        && !hiddenIDs.contains($0.applicationID)
                }
                .sorted {
                    ($0.accessedAt, $0.applicationID) > ($1.accessedAt, $1.applicationID)
                }
                .filter { seen.insert($0.applicationID).inserted }
                .prefix(maximumCount)
        )
    }

    public func grouped(
        _ history: [RecentApplication], calendar: Calendar
    ) -> [(day: Date, applications: [RecentApplication])] {
        let groups = Dictionary(grouping: history) { calendar.startOfDay(for: $0.accessedAt) }
        return groups.keys.sorted(by: >).map { day in
            (day, groups[day, default: []].sorted { $0.accessedAt > $1.accessedAt })
        }
    }
}

public enum RecentsError: Error, Equatable, Sendable {
    case invalidRetentionDays
    case invalidMaximumCount
}
