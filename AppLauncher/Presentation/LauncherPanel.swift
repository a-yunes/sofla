import AppKit

final class LauncherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    var onEscape: (() -> Void)?
    var onHorizontalNavigation: ((Int) -> Void)?
    var onPageScroll: ((Int) -> Bool)?
    var allowsPageScroll: (() -> Bool)?
    private var scrollPaging = ScrollPagingPolicy()

    func updateScrollThreshold(_ threshold: CGFloat) {
        scrollPaging.updateThreshold(threshold)
    }

    override func scrollWheel(with event: NSEvent) {
        guard allowsPageScroll?() == true else {
            super.scrollWheel(with: event)
            return
        }
        let value =
            abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
            ? event.scrollingDeltaX : event.scrollingDeltaY
        let phase = ScrollPagingPolicy.Phase(eventPhase: event.phase)
        guard
            let delta = scrollPaging.pageDelta(
                scrollingDelta: value,
                phase: phase,
                hasMomentum: !event.momentumPhase.isEmpty,
                timestamp: event.timestamp
            )
        else { return }
        if onPageScroll?(delta) != true {
            super.scrollWheel(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) { onEscape?() }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: onEscape?()
        case 123: onHorizontalNavigation?(-1)
        case 124: onHorizontalNavigation?(1)
        default: super.keyDown(with: event)
        }
    }
}

nonisolated struct ScrollPagingPolicy {
    enum Phase {
        case discrete
        case began
        case changed
        case ended
        case cancelled

        init(eventPhase: NSEvent.Phase) {
            if eventPhase.contains(.began) {
                self = .began
            } else if eventPhase.contains(.ended) {
                self = .ended
            } else if eventPhase.contains(.cancelled) {
                self = .cancelled
            } else if eventPhase.isEmpty {
                self = .discrete
            } else {
                self = .changed
            }
        }
    }

    private static let discreteCooldown: TimeInterval = 0.18

    private var threshold: CGFloat
    private var accumulatedDelta: CGFloat = 0
    private var consumedGesture = false
    private var lastDiscretePageTime: TimeInterval = -.infinity

    init(threshold: CGFloat = 12) {
        precondition(threshold > 0)
        self.threshold = threshold
    }

    mutating func updateThreshold(_ threshold: CGFloat) {
        precondition(threshold > 0)
        self.threshold = threshold
        accumulatedDelta = 0
        consumedGesture = false
    }

    mutating func pageDelta(
        scrollingDelta: CGFloat,
        phase: Phase,
        hasMomentum: Bool,
        timestamp: TimeInterval
    ) -> Int? {
        guard !hasMomentum else { return nil }
        switch phase {
        case .discrete:
            guard abs(scrollingDelta) >= 0.1,
                timestamp - lastDiscretePageTime >= Self.discreteCooldown
            else { return nil }
            lastDiscretePageTime = timestamp
            return scrollingDelta < 0 ? 1 : -1
        case .began:
            accumulatedDelta = scrollingDelta
            consumedGesture = false
        case .changed:
            accumulatedDelta += scrollingDelta
        case .ended:
            accumulatedDelta += scrollingDelta
        case .cancelled:
            accumulatedDelta = 0
            consumedGesture = false
            return nil
        }

        let pageDelta: Int?
        if !consumedGesture, abs(accumulatedDelta) >= threshold {
            consumedGesture = true
            pageDelta = accumulatedDelta < 0 ? 1 : -1
        } else {
            pageDelta = nil
        }
        if phase == .ended {
            accumulatedDelta = 0
            consumedGesture = false
        }
        return pageDelta
    }
}
