import Foundation

/// Karabiner-Elements can seize the Pro Click Mini, after which its raw HID values no longer
/// reach `DeviceTagger` and tilts can't be told apart from other scrolling.
public enum KarabinerCheck {
    public static let defaultConfigURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/karabiner/karabiner.json")

    /// True when the selected Karabiner profile has a device entry for this mouse that isn't
    /// set to `"ignore": true`. False when Karabiner isn't configured at all.
    public static func grabsProClick(configURL: URL = defaultConfigURL,
                                     vendorID: Int = 0x1532, productID: Int = 0x009B) -> Bool {
        guard let data = try? Data(contentsOf: configURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profiles = root["profiles"] as? [[String: Any]] else { return false }
        let profile = profiles.first { $0["selected"] as? Bool == true } ?? profiles.first
        let devices = profile?["devices"] as? [[String: Any]] ?? []
        return devices.contains { device in
            let ids = device["identifiers"] as? [String: Any] ?? [:]
            guard ids["vendor_id"] as? Int == vendorID, ids["product_id"] as? Int == productID else { return false }
            return device["ignore"] as? Bool != true
        }
    }
}
