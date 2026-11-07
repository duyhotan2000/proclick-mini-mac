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

public enum EngineChange: Equatable, Sendable {
    case start, stop, none
}

/// The engine runs exactly while Accessibility and Input Monitoring are granted. Stopping it on
/// revocation lets a re-grant create a fresh, working event tap.
public func engineChange(running: Bool, trusted: Bool, listening: Bool) -> EngineChange {
    let allowed = trusted && listening
    if allowed && !running { return .start }
    if !allowed && running { return .stop }
    return .none
}

/// Whether the menu should warn that tilt switching isn't working yet.
public func needsAttention(onboarding: OnboardingState, engineProblem: String?) -> Bool {
    onboarding != .ready || engineProblem != nil
}
