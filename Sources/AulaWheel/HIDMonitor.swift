import AulaWheelCore
import Foundation
import IOKit.hid

/// Watches the AULA keyboard for connects/disconnects and its vendor "knob is in RGB mode" report.
final class HIDMonitor {
    var onConnect: (() -> Void)?
    var onVendorPing: (() -> Void)?

    private var match = DeviceMatch()
    private var devices: [IOHIDDevice: (productID: Int?, support: DeviceSupport)] = [:]
    private var manager: IOHIDManager?

    // Input report the firmware sends on every knob action while the knob drives the LEDs.
    private static let vendorReportID: UInt32 = 0x13

    var isConnected: Bool { !devices.isEmpty }

    /// Product IDs of connected devices that are used but not verified.
    var unverifiedProductIDs: [Int] {
        Set(devices.values.filter { $0.support == .unverified }.compactMap(\.productID)).sorted()
    }

    func start(device: DeviceMatch) {
        stop()
        match = device
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching = device.productIDs.map {
            [kIOHIDVendorIDKey: device.vendorID, kIOHIDProductIDKey: $0] as [String: Any]
        } + [[
            kIOHIDVendorIDKey: device.vendorID,
            kIOHIDDeviceUsagePageKey: kHIDPage_Consumer,
            kIOHIDDeviceUsageKey: kHIDUsage_Csmr_ConsumerControl,
        ]]
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            guard let context else { return }
            Unmanaged<HIDMonitor>.fromOpaque(context).takeUnretainedValue().added(device)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context else { return }
            Unmanaged<HIDMonitor>.fromOpaque(context).takeUnretainedValue().devices[device] = nil
        }, context)
        IOHIDManagerRegisterInputReportCallback(manager, { context, _, sender, _, reportID, _, _ in
            guard let context, let sender, reportID == HIDMonitor.vendorReportID else { return }
            let monitor = Unmanaged<HIDMonitor>.fromOpaque(context).takeUnretainedValue()
            // The report's meaning is only known for the verified firmware.
            let device = Unmanaged<IOHIDDevice>.fromOpaque(sender).takeUnretainedValue()
            guard monitor.devices[device]?.support == .verified else { return }
            monitor.onVendorPing?()
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
        devices.removeAll()
    }

    private func added(_ device: IOHIDDevice) {
        let productID = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int
        guard let support = match.support(
            vendorID: IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int,
            productID: productID,
            sendsVolumeKeys: IOHIDDeviceConformsTo(device, UInt32(kHIDPage_Consumer), UInt32(kHIDUsage_Csmr_ConsumerControl))
        ) else { return }
        devices[device] = (productID, support)
        onConnect?()
    }
}
