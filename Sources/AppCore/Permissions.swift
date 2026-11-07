import AppKit
import ApplicationServices
import CoreBluetooth
import IOKit.hid

public enum OnboardingState: Equatable, Sendable {
    case ready
    case needsAccessibility
    case needsInputMonitoring
    case needsBluetooth
    case bluetoothOff
}

/// What the user still has to do, most blocking first: Bluetooth permission, Bluetooth on,
/// then Accessibility (needed to intercept tilts), then Input Monitoring (to tell the mouse
/// apart from other devices).
public func onboardingState(accessibilityTrusted: Bool, bluetooth: CBManagerAuthorization, poweredOn: Bool,
                            inputMonitoring: Bool = true) -> OnboardingState {
    if bluetooth != .allowedAlways { return .needsBluetooth }
    if !poweredOn { return .bluetoothOff }
    if !accessibilityTrusted { return .needsAccessibility }
    if !inputMonitoring { return .needsInputMonitoring }
    return .ready
}

public enum Permissions {
    /// `prompt` shows the system's "would like to control this computer" dialog once.
    public static func accessibilityTrusted(prompt: Bool = false) -> Bool {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": prompt] as CFDictionary)
    }

    public static func inputMonitoringGranted() -> Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    public static func requestInputMonitoring() {
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    public static func openSettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}
