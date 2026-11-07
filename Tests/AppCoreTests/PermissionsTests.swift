import CoreBluetooth
import Testing
@testable import AppCore

@Test func readyWhenEverythingGranted() {
    #expect(onboardingState(accessibilityTrusted: true, bluetooth: .allowedAlways, poweredOn: true) == .ready)
}

@Test func onboardingStateWithoutAccessibility() {
    #expect(onboardingState(accessibilityTrusted: false, bluetooth: .allowedAlways, poweredOn: true)
        == .needsAccessibility)
}

@Test func bluetoothDeniedComesFirst() {
    for auth in [CBManagerAuthorization.denied, .restricted, .notDetermined] {
        for trusted in [true, false] {
            for on in [true, false] {
                #expect(onboardingState(accessibilityTrusted: trusted, bluetooth: auth, poweredOn: on) == .needsBluetooth)
            }
        }
    }
}

@Test func bluetoothOffBeforeAccessibility() {
    #expect(onboardingState(accessibilityTrusted: false, bluetooth: .allowedAlways, poweredOn: false) == .bluetoothOff)
    #expect(onboardingState(accessibilityTrusted: true, bluetooth: .allowedAlways, poweredOn: false) == .bluetoothOff)
}

@Test func inputMonitoringAfterAccessibility() {
    #expect(onboardingState(accessibilityTrusted: true, bluetooth: .allowedAlways, poweredOn: true,
                            inputMonitoring: false) == .needsInputMonitoring)
    #expect(onboardingState(accessibilityTrusted: false, bluetooth: .allowedAlways, poweredOn: true,
                            inputMonitoring: false) == .needsAccessibility)
}
