import Foundation
import IOKit.hid

/// Watches the AULA keyboard for connects/disconnects and its vendor "knob is in RGB mode" report.
final class HIDMonitor {
    var onConnect: (() -> Void)?
    var onVendorPing: (() -> Void)?

    private(set) var deviceCount = 0
    private var manager: IOHIDManager?

    // Input report the firmware sends on every knob action while the knob drives the LEDs.
    private static let vendorReportID: UInt32 = 0x13

    func start(vendorID: Int, productID: Int) {
        stop()
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDVendorIDKey: vendorID,
            kIOHIDProductIDKey: productID,
        ] as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, _ in
            guard let context else { return }
            let monitor = Unmanaged<HIDMonitor>.fromOpaque(context).takeUnretainedValue()
            monitor.deviceCount += 1
            monitor.onConnect?()
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, _ in
            guard let context else { return }
            let monitor = Unmanaged<HIDMonitor>.fromOpaque(context).takeUnretainedValue()
            monitor.deviceCount = max(0, monitor.deviceCount - 1)
        }, context)
        IOHIDManagerRegisterInputReportCallback(manager, { context, _, _, _, reportID, _, _ in
            guard let context, reportID == HIDMonitor.vendorReportID else { return }
            Unmanaged<HIDMonitor>.fromOpaque(context).takeUnretainedValue().onVendorPing?()
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager
    }

    func stop() {
        guard let manager else { return }
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = nil
        deviceCount = 0
    }
}
