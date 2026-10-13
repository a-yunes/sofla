import CoreServices
import Foundation

nonisolated struct CatalogChangeEvent: Equatable, Sendable {
    let path: URL
    let flags: UInt32

    var hasItemSpecificChange: Bool {
        let itemFlags =
            UInt32(kFSEventStreamEventFlagItemCreated)
            | UInt32(kFSEventStreamEventFlagItemRemoved)
            | UInt32(kFSEventStreamEventFlagItemInodeMetaMod)
            | UInt32(kFSEventStreamEventFlagItemRenamed)
            | UInt32(kFSEventStreamEventFlagItemModified)
            | UInt32(kFSEventStreamEventFlagItemFinderInfoMod)
            | UInt32(kFSEventStreamEventFlagItemChangeOwner)
            | UInt32(kFSEventStreamEventFlagItemXattrMod)
            | UInt32(kFSEventStreamEventFlagItemCloned)
        return flags & itemFlags != 0
    }

    var requiresFullInvalidation: Bool {
        let fullFlags =
            UInt32(kFSEventStreamEventFlagMustScanSubDirs)
            | UInt32(kFSEventStreamEventFlagUserDropped)
            | UInt32(kFSEventStreamEventFlagKernelDropped)
            | UInt32(kFSEventStreamEventFlagEventIdsWrapped)
            | UInt32(kFSEventStreamEventFlagRootChanged)
            | UInt32(kFSEventStreamEventFlagMount)
            | UInt32(kFSEventStreamEventFlagUnmount)
        if flags & fullFlags != 0 { return true }
        let informationalAndTypeFlags =
            UInt32(kFSEventStreamEventFlagHistoryDone)
            | UInt32(kFSEventStreamEventFlagItemIsFile)
            | UInt32(kFSEventStreamEventFlagItemIsDir)
            | UInt32(kFSEventStreamEventFlagItemIsSymlink)
            | UInt32(kFSEventStreamEventFlagOwnEvent)
            | UInt32(kFSEventStreamEventFlagItemIsHardlink)
            | UInt32(kFSEventStreamEventFlagItemIsLastHardlink)
        let knownFlags =
            fullFlags | informationalAndTypeFlags
            | UInt32(kFSEventStreamEventFlagItemCreated)
            | UInt32(kFSEventStreamEventFlagItemRemoved)
            | UInt32(kFSEventStreamEventFlagItemInodeMetaMod)
            | UInt32(kFSEventStreamEventFlagItemRenamed)
            | UInt32(kFSEventStreamEventFlagItemModified)
            | UInt32(kFSEventStreamEventFlagItemFinderInfoMod)
            | UInt32(kFSEventStreamEventFlagItemChangeOwner)
            | UInt32(kFSEventStreamEventFlagItemXattrMod)
            | UInt32(kFSEventStreamEventFlagItemCloned)
        return flags & ~knownFlags != 0
    }
}

nonisolated struct CatalogChangeBatch: Equatable, Sendable {
    static let maximumEventCount = 4_096

    let events: [CatalogChangeEvent]
    let requiresFullInvalidation: Bool

    init(events: [CatalogChangeEvent], requiresFullInvalidation: Bool = false) {
        self.events = events
        self.requiresFullInvalidation =
            requiresFullInvalidation || events.contains(where: \.requiresFullInvalidation)
    }

    static let unresolved = Self(events: [], requiresFullInvalidation: true)

    var changedPaths: [URL] { events.map(\.path) }

    func merged(with other: Self) -> Self {
        guard events.count + other.events.count <= Self.maximumEventCount else {
            return .unresolved
        }
        return Self(
            events: events + other.events,
            requiresFullInvalidation: requiresFullInvalidation || other.requiresFullInvalidation
        )
    }
}

/// Directory notifications invalidate the catalog. The scanner remains the source of truth.
@MainActor
final class CatalogChangeObserver {
    private var stream: FSEventStreamRef?
    private var task: Task<Void, Never>?
    private var flushTask: Task<Void, Never>?
    private var continuation: AsyncStream<CatalogChangeBatch>.Continuation?
    private var pendingBatch: CatalogChangeBatch?

    func start(
        roots: [URL], changed: @escaping @MainActor (CatalogChangeBatch) -> Void
    ) {
        stop()
        let (events, continuation) = AsyncStream<CatalogChangeBatch>.makeStream(
            bufferingPolicy: .bufferingNewest(1))
        self.continuation = continuation
        let box = CatalogEventCallbacks.Box(continuation: continuation)
        let opaque = Unmanaged.passRetained(box).toOpaque()
        var context = FSEventStreamContext(
            version: 0,
            info: opaque,
            retain: nil,
            release: CatalogEventCallbacks.release,
            copyDescription: nil
        )
        stream = FSEventStreamCreate(
            nil,
            CatalogEventCallbacks.receive,
            &context,
            roots.map(\.path) as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1,
            FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagWatchRoot
                    | kFSEventStreamCreateFlagFileEvents
                    | kFSEventStreamCreateFlagUseCFTypes)
        )
        guard let stream else {
            Unmanaged<CatalogEventCallbacks.Box>.fromOpaque(opaque).release()
            self.continuation = nil
            continuation.finish()
            return
        }
        FSEventStreamSetDispatchQueue(stream, DispatchQueue(label: "app-launcher.catalog-events"))
        guard FSEventStreamStart(stream) else {
            stop()
            return
        }
        task = Task { @MainActor in
            for await batch in events {
                guard !Task.isCancelled else { break }
                self.accumulate(batch, changed: changed)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        flushTask?.cancel()
        flushTask = nil
        pendingBatch = nil
        continuation?.finish()
        continuation = nil
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        stream = nil
    }

    private func accumulate(
        _ batch: CatalogChangeBatch, changed: @escaping @MainActor (CatalogChangeBatch) -> Void
    ) {
        pendingBatch = pendingBatch?.merged(with: batch) ?? batch
        flushTask?.cancel()
        flushTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled, let self, let pending = self.pendingBatch else { return }
                self.pendingBatch = nil
                self.flushTask = nil
                changed(pending)
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
    }
}

nonisolated private enum CatalogEventCallbacks {
    final class Box: Sendable {
        let continuation: AsyncStream<CatalogChangeBatch>.Continuation

        init(continuation: AsyncStream<CatalogChangeBatch>.Continuation) {
            self.continuation = continuation
        }
    }

    static let release: CFAllocatorReleaseCallBack = { info in
        guard let info else { return }
        Unmanaged<Box>.fromOpaque(info).release()
    }

    static let receive: FSEventStreamCallback = { _, info, count, rawPaths, flags, _ in
        guard let info else { return }
        let box = Unmanaged<Box>.fromOpaque(info).takeUnretainedValue()
        guard count > 0 else {
            _ = box.continuation.yield(.unresolved)
            return
        }
        guard count <= CatalogChangeBatch.maximumEventCount else {
            _ = box.continuation.yield(.unresolved)
            return
        }
        let pathArray = Unmanaged<CFArray>.fromOpaque(rawPaths).takeUnretainedValue() as NSArray
        guard pathArray.count == count else {
            _ = box.continuation.yield(.unresolved)
            return
        }
        var events: [CatalogChangeEvent] = []
        events.reserveCapacity(count)
        for index in 0..<count {
            guard let path = pathArray[index] as? String, !path.isEmpty else {
                _ = box.continuation.yield(.unresolved)
                return
            }
            events.append(
                CatalogChangeEvent(
                    path: URL(fileURLWithPath: path), flags: flags[index]))
        }
        let result = box.continuation.yield(CatalogChangeBatch(events: events))
        if case .dropped = result {
            _ = box.continuation.yield(.unresolved)
        }
    }
}
