import Foundation
import UserNotifications

/// Decides when to warn about a low battery: once when it falls to 15% or below, and again
/// only after it has recovered above 20% (a fresh battery).
public struct LowBatteryNotifier: Sendable {
    public static let threshold = 15
    public static let rearmAbove = 20
    private var armed = true

    public init() {}

    /// True when a notification should be posted now.
    public mutating func update(percent: Int) -> Bool {
        if percent > Self.rearmAbove { armed = true }
        guard armed, percent <= Self.threshold else { return false }
        armed = false
        return true
    }

    static func post(percent: Int) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Pro Click Mini battery low"
            content.body = "\(percent)% left. Replace the AA battery soon."
            UNUserNotificationCenter.current()
                .add(UNNotificationRequest(identifier: "low-battery", content: content, trigger: nil))
        }
    }
}
