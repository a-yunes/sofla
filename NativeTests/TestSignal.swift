import Foundation

/// A bounded event counter for controlled async fixtures. Every waiter is removed on success,
/// timeout, or cancellation, so a failed prerequisite cannot strand the test runner.
actor TestSignal {
    private var count = 0
    private var waiters: [UUID: (Int, CheckedContinuation<Bool, Never>)] = [:]

    func advance() {
        count += 1
        let completed = waiters.filter { count >= $0.value.0 }
        for (id, waiter) in completed {
            waiters.removeValue(forKey: id)
            waiter.1.resume(returning: true)
        }
    }

    func wait(for target: Int = 1, timeout: Duration = .seconds(5)) async -> Bool {
        if count >= target { return true }
        let id = UUID()
        let timeoutTask = Task {
            do {
                try await Task.sleep(for: timeout)
                finish(id: id)
            } catch {}
        }
        defer { timeoutTask.cancel() }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if count >= target || Task.isCancelled {
                    continuation.resume(returning: count >= target)
                } else {
                    waiters[id] = (target, continuation)
                }
            }
        } onCancel: {
            Task { await self.finish(id: id) }
        }
    }

    private func finish(id: UUID) {
        waiters.removeValue(forKey: id)?.1.resume(returning: false)
    }
}
