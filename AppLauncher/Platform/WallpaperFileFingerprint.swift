import Foundation

nonisolated struct WallpaperFileFingerprint: Sendable, Equatable {
    let deviceID: UInt64
    let fileID: UInt64
    let modificationDate: Date
    let byteCount: UInt64

    @concurrent
    static func read(from url: URL) async throws -> Self {
        try Task.checkCancellation()
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard
            let deviceID = attributes[.systemNumber] as? NSNumber,
            let fileID = attributes[.systemFileNumber] as? NSNumber,
            let modificationDate = attributes[.modificationDate] as? Date,
            let byteCount = attributes[.size] as? NSNumber
        else {
            throw WallpaperFileFingerprintError.missingRequiredAttribute
        }
        try Task.checkCancellation()
        return Self(
            deviceID: deviceID.uint64Value,
            fileID: fileID.uint64Value,
            modificationDate: modificationDate,
            byteCount: byteCount.uint64Value
        )
    }
}

nonisolated private enum WallpaperFileFingerprintError: Error {
    case missingRequiredAttribute
}
