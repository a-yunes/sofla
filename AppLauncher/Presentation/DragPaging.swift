import Foundation

extension LauncherModel {
    func startDragPaging(_ delta: Int) {
        stopDragPaging()
        guard canDrag, draggedItem != nil else { return }
        dragPageTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(500))
                while !Task.isCancelled {
                    guard let self, self.draggedItem != nil else { return }
                    guard await self.changePageWhenReady(delta) else { return }
                    try await Task.sleep(for: .milliseconds(750))
                }
            } catch is CancellationError { return } catch { return }
        }
    }

    func stopDragPaging() {
        dragPageTask?.cancel()
        dragPageTask = nil
    }
}
