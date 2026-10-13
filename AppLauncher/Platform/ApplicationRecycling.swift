import AppKit

@MainActor
protocol ApplicationRecycling {
    func recycle(_ url: URL) async throws -> [URL: URL]
}

@MainActor
struct WorkspaceApplicationRecycler: ApplicationRecycling {
    typealias Operation = @MainActor (URL) async throws -> [URL: URL]

    private let operation: Operation?

    init(operation: Operation? = nil) {
        self.operation = operation
    }

    func recycle(_ url: URL) async throws -> [URL: URL] {
        if let operation {
            return try await operation(url)
        }
        return try await withCheckedThrowingContinuation { continuation in
            NSWorkspace.shared.recycle([url]) { newURLs, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: newURLs)
                }
            }
        }
    }
}
