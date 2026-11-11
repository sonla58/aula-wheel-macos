import AulaWheelCore
import Foundation
import IOKit.hid
import IOKit.hidsystem

/// Per-device key remapping on the AULA's HID services, so no other keyboard is affected.
///
/// Uses the IOHIDEventSystemClient API in-process: spawning `hidutil` and waiting for it would
/// spin the main run loop and let other work interleave with enabling/disabling.
final class KeyRemapper {
    let vendorID: Int
    let productID: Int
    private let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
    private static let property = "UserKeyMapping" as CFString
    private static let sourceKey = "HIDKeyboardModifierMappingSrc"
    private static let destinationKey = "HIDKeyboardModifierMappingDst"

    init(vendorID: Int, productID: Int) {
        self.vendorID = vendorID
        self.productID = productID
    }

    /// Returns false when the keyboard is not connected or a service refused the change.
    @discardableResult
    func apply() -> Bool { update(applying: true) }

    @discardableResult
    func clear() -> Bool { update(applying: false) }

    /// Whether every connected AULA service carries this app's entries; nil when none is connected.
    func isApplied() -> Bool? {
        let services = matchingServices()
        guard !services.isEmpty else { return nil }
        let ours = Set(ConsumerRemap.entries.map(\.source))
        return services.allSatisfy { service in
            let present = Set(currentMapping(service).compactMap(Self.source(of:)))
            return ours.isSubset(of: present)
        }
    }

    private func update(applying: Bool) -> Bool {
        let services = matchingServices()
        var ok = !services.isEmpty
        for service in services {
            let updated = ConsumerRemap.updated(
                currentMapping(service),
                applying: applying,
                source: Self.source(of:),
                make: { [Self.sourceKey: NSNumber(value: $0.source), Self.destinationKey: NSNumber(value: $0.destination)] as Any }
            )
            if !IOHIDServiceClientSetProperty(service, Self.property, updated as CFArray) {
                NSLog("AulaWheel: could not set UserKeyMapping on HID service")
                ok = false
            }
        }
        return ok
    }

    /// Items of any shape are kept as-is so a mapping we do not understand is never dropped.
    private func currentMapping(_ service: IOHIDServiceClient) -> [Any] {
        IOHIDServiceClientCopyProperty(service, Self.property) as? [Any] ?? []
    }

    private static func source(of item: Any) -> UInt64? {
        ((item as? [String: Any])?[sourceKey] as? NSNumber)?.uint64Value
    }

    private func matchingServices() -> [IOHIDServiceClient] {
        let services = IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] ?? []
        return services.filter {
            (IOHIDServiceClientCopyProperty($0, kIOHIDVendorIDKey as CFString) as? Int) == vendorID
                && (IOHIDServiceClientCopyProperty($0, kIOHIDProductIDKey as CFString) as? Int) == productID
        }
    }
}
