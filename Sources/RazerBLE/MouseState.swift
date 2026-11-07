import Foundation

/// The mouse's on-device settings that this app reads and writes.
public struct MouseState: Codable, Equatable, Sendable {
    public var dpi: DPITable
    public var sleepSeconds: UInt16

    public init(dpi: DPITable, sleepSeconds: UInt16) {
        self.dpi = dpi
        self.sleepSeconds = sleepSeconds
    }
}

public enum Defaults {
    static let stockStages: [DPIStage] = [
        DPIStage(id: 1, x: 400, y: 400),
        DPIStage(id: 2, x: 800, y: 800),
        DPIStage(id: 3, x: 1600, y: 1600),
        DPIStage(id: 4, x: 3200, y: 3200),
        DPIStage(id: 5, x: 6400, y: 6400),
    ]

    /// Factory defaults from the Razer master guide: active 1600, sleep 5 min.
    public static let factory = MouseState(dpi: DPITable(activeID: 3, stages: stockStages), sleepSeconds: 300)

    /// The owner's mouse as first probed on 2026-11-06 (see docs/device-baseline.json).
    public static let baseline = MouseState(dpi: DPITable(activeID: 4, stages: stockStages), sleepSeconds: 300)
}

public enum Limits {
    public static let dpiRange: ClosedRange<UInt16> = 100...12000
    public static let dpiStep: UInt16 = 50
    public static let stageCount: ClosedRange<Int> = 1...5
    public static let sleepRange: ClosedRange<UInt16> = 60...900
}

public struct ValidationError: Error, Equatable {
    public let message: String
}

public func validate(_ s: MouseState) throws {
    guard Limits.stageCount.contains(s.dpi.stages.count) else {
        throw ValidationError(message: "Use between 1 and 5 DPI stages.")
    }
    for (i, stage) in s.dpi.stages.enumerated() {
        for v in [stage.x, stage.y] where !Limits.dpiRange.contains(v) || v % Limits.dpiStep != 0 {
            throw ValidationError(message: "Stage \(i + 1): DPI must be 100–12000 in steps of 50 (got \(v)).")
        }
    }
    guard Limits.sleepRange.contains(s.sleepSeconds) else {
        throw ValidationError(message: "Sleep timer must be 1–15 minutes (got \(s.sleepSeconds) s).")
    }
}
