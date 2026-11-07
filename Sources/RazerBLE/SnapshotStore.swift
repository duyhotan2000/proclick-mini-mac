import Foundation

/// Timestamped JSON copies of the mouse's settings, saved before every write.
public struct SnapshotStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// `~/Library/Application Support/ProClickMini/snapshots/`
    public static var `default`: SnapshotStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return SnapshotStore(directory: base.appendingPathComponent("ProClickMini/snapshots", isDirectory: true))
    }

    public func save(_ s: MouseState, reason: String) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        var url = directory.appendingPathComponent("\(formatter.string(from: Date()))-\(reason).json")
        // Two saves in the same millisecond must not overwrite each other.
        var n = 1
        while FileManager.default.fileExists(atPath: url.path) {
            url = directory.appendingPathComponent("\(formatter.string(from: Date()))-\(n)-\(reason).json")
            n += 1
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(s).write(to: url, options: .atomic)
        return url
    }

    /// Snapshot files, oldest first.
    public func list() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey])
            .filter { $0.pathExtension == "json" }
            .sorted { lhs, rhs in
                let l = (try? lhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let r = (try? rhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return l == r ? lhs.lastPathComponent < rhs.lastPathComponent : l < r
            }
    }

    /// Records `s` as this mouse's original settings, unless one was recorded already.
    /// Returns whether it saved.
    @discardableResult
    public func saveOriginalIfMissing(_ s: MouseState, mouse: UUID) throws -> Bool {
        let url = originalURL(mouse)
        guard !FileManager.default.fileExists(atPath: url.path) else { return false }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(s).write(to: url, options: .withoutOverwriting)
        return true
    }

    /// The settings this mouse had when the app first saw it.
    public func original(for mouse: UUID) -> MouseState? {
        guard let data = try? Data(contentsOf: originalURL(mouse)) else { return nil }
        return try? JSONDecoder().decode(MouseState.self, from: data)
    }

    private func originalURL(_ mouse: UUID) -> URL {
        directory.appendingPathComponent("originals/\(mouse.uuidString).json")
    }

    public func latest() throws -> MouseState? {
        guard let url = try list().last else { return nil }
        return try JSONDecoder().decode(MouseState.self, from: Data(contentsOf: url))
    }
}
