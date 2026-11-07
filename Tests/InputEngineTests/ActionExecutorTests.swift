import Testing
@testable import InputEngine

@Test func backForwardUseShortcutsInAppsIgnoringSideButtons() {
    #expect(BackForward.shortcutKey(.back, frontApp: "com.apple.Safari") == 33)     // ⌘[
    #expect(BackForward.shortcutKey(.forward, frontApp: "com.apple.finder") == 30)  // ⌘]
    #expect(BackForward.shortcutKey(.back, frontApp: "com.google.Chrome") == nil)
    #expect(BackForward.shortcutKey(.back, frontApp: nil) == nil)
}
