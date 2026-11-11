import AulaWheelCore
import Foundation

/// Drives `ScrollAnimator` at a fixed frame rate while there is distance left to scroll.
final class ScrollEngine {
    private var animator: ScrollAnimator
    private var timer: DispatchSourceTimer?
    private var lastFrame: TimeInterval = 0
    private let poster: EventPoster

    init(poster: EventPoster, duration: TimeInterval) {
        self.poster = poster
        self.animator = ScrollAnimator(duration: duration)
    }

    var duration: TimeInterval {
        get { animator.duration }
        set { animator.duration = newValue }
    }

    func add(dx: Double, dy: Double) {
        animator.add(dx: dx, dy: dy)
        guard timer == nil else { return }
        lastFrame = Clock.now()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .nanoseconds(1_000_000_000 / 120), leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in self?.frame() }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
        animator.reset()
    }

    private func frame() {
        let now = Clock.now()
        let dt = min(max(now - lastFrame, 0), 0.05)
        lastFrame = now
        let delta = animator.step(dt: dt)
        poster.postScroll(dx: delta.dx, dy: delta.dy)
        if animator.isIdle {
            timer?.cancel()
            timer = nil
        }
    }
}
