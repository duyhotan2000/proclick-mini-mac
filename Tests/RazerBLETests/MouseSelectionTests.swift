import Foundation
import Testing
@testable import RazerBLE

private let a = UUID(), b = UUID(), c = UUID()

@Test func candidateNamesMatchProClickOnly() {
    #expect(MouseSelection.isCandidate(name: "ProClickM"))
    #expect(MouseSelection.isCandidate(name: "Pro Click Mini"))
    #expect(!MouseSelection.isCandidate(name: "BSK X HS"))
    #expect(!MouseSelection.isCandidate(name: nil))
}

@Test func parsesPnPID() {
    let id = MouseSelection.parsePnPID([0x02, 0x32, 0x15, 0x9B, 0x00, 0x01, 0x00])
    #expect(id?.vendor == 0x1532 && id?.product == 0x009B)
    #expect(MouseSelection.parsePnPID([0x02, 0x32, 0x15]) == nil)
}

@Test func onlyProClickMiniPnPIsAccepted() {
    #expect(MouseSelection.isProClickMini(vendor: 0x1532, product: 0x009B))
    #expect(!MouseSelection.isProClickMini(vendor: 0x1532, product: 0x0077))
}

@Test func picksPreferredMouseWhenConnected() {
    let mice = [MouseInfo(id: a, name: "ProClickM"), MouseInfo(id: b, name: "ProClickM")]
    #expect(MouseSelection.pick(mice, preferred: b, rejected: [])?.id == b)
    #expect(MouseSelection.pick(mice, preferred: c, rejected: [])?.id == a)  // preferred one is off
    #expect(MouseSelection.pick(mice, preferred: nil, rejected: [])?.id == a)
}

@Test func skipsRejectedDevices() {
    let mice = [MouseInfo(id: a, name: "ProClickM"), MouseInfo(id: b, name: "ProClickM")]
    #expect(MouseSelection.pick(mice, preferred: a, rejected: [a])?.id == b)
    #expect(MouseSelection.pick([mice[0]], preferred: nil, rejected: [a]) == nil)
}

@Test func connectAttemptExpires() {
    #expect(!MouseSelection.connectExpired(startedAt: 100, now: 105))
    #expect(MouseSelection.connectExpired(startedAt: 100, now: 111))
}
