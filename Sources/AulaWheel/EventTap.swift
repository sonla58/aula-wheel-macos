import CoreGraphics
import Foundation

/// Active session event tap that swallows the knob's key codes and reports them on the main queue.
///
/// The tap runs on its own thread: every keystroke the user types waits for the tap callback,
/// so it must never queue behind UI work on the main thread.
final class EventTap {
    struct KeyEvent {
        var keyCode: UInt16
        var isDown: Bool
        var isRepeat: Bool
        var flags: UInt64
        var timestamp: UInt64
        /// Which `start()` produced the event, so events queued before a stop can be dropped.
        var generation: Int
    }

    /// Called on the main queue, in event order.
    var onKey: ((KeyEvent) -> Void)?

    private let lock = NSLock()
    private var watched: Set<UInt16> = []
    private var tap: CFMachPort?
    private var runLoop: CFRunLoop?
    private var currentGeneration = 0
    private let ownPID = Int64(getpid())

    var watchedKeyCodes: Set<UInt16> {
        get { lock.withLock { watched } }
        set { lock.withLock { watched = newValue } }
    }

    var generation: Int { lock.withLock { currentGeneration } }

    var isRunning: Bool {
        guard let tap = lock.withLock({ tap }) else { return false }
        return CGEvent.tapIsEnabled(tap: tap)
    }

    /// `stop()` advances the generation, so the new tap's events carry it from the first one.
    func start() -> Bool {
        stop()
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        let ready = DispatchSemaphore(value: 0)
        var threadRunLoop: CFRunLoop?
        let thread = Thread {
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            threadRunLoop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(threadRunLoop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "AulaWheel.EventTap"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()

        lock.withLock {
            self.tap = tap
            self.runLoop = threadRunLoop
        }
        return true
    }

    func stop() {
        let (tap, runLoop) = lock.withLock { () -> (CFMachPort?, CFRunLoop?) in
            defer {
                self.tap = nil
                self.runLoop = nil
            }
            return (self.tap, self.runLoop)
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoop { CFRunLoopStop(runLoop) }
        // Advanced only after the old tap is disabled, so its last events keep the old generation.
        lock.withLock { currentGeneration += 1 }
    }

    /// Runs on the tap thread.
    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = lock.withLock({ tap }) { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let code = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        guard watchedKeyCodes.contains(code),
              event.getIntegerValueField(.eventSourceUnixProcessID) != ownPID
        else { return Unmanaged.passUnretained(event) }

        let keyEvent = KeyEvent(
            keyCode: code,
            isDown: type == .keyDown,
            isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
            flags: event.flags.rawValue,
            timestamp: event.timestamp,
            generation: generation
        )
        DispatchQueue.main.async { [weak self] in self?.onKey?(keyEvent) }
        return nil
    }
}

private func eventTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    return Unmanaged<EventTap>.fromOpaque(refcon).takeUnretainedValue().handle(type: type, event: event)
}
