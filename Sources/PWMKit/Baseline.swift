import Foundation

/// A known-good set of property values, saved so a stuck panel can be put back.
///
/// Only writable scalars are recorded, because those are the ones that can be written back. Values
/// are stored as the literals `PropertyValue.parse` accepts, so the file can be hand-edited.
public struct Baseline: Codable, Sendable {
    public let build: String
    public let captured: String
    /// display name -> property key (as published) -> value literal
    public let displays: [String: [String: String]]

    public init(build: String, captured: String, displays: [String: [String: String]]) {
        self.build = build
        self.captured = captured
        self.displays = displays
    }

    /// Default settle interval between the two reads that filter out live telemetry.
    public static let settleInterval: TimeInterval = 0.3

    public static func capture(
        _ nodes: [Framebuffer], build: String = Baseline.currentBuild, captured: Date = Date(),
        settleInterval: TimeInterval = Baseline.settleInterval
    ) throws -> Baseline {
        var first: [String: [String: PropertyValue]] = [:]
        for node in nodes { first[node.name] = try node.read() }
        Thread.sleep(forTimeInterval: settleInterval)

        var displays: [String: [String: String]] = [:]
        for node in nodes {
            displays[node.name] = stableSettings(
                first: first[node.name] ?? [:], second: try node.read())
        }
        return Baseline(
            build: build,
            captured: ISO8601DateFormatter().string(from: captured),
            displays: displays)
    }

    /// Keeps only keys worth restoring: a catalogued runtime property, a writable scalar, and the
    /// same in both reads. Values that move on their own are readings, not settings - the ambient
    /// light level is the obvious one, and writing a stale sample back would be wrong.
    public static func stableSettings(
        first: [String: PropertyValue], second: [String: PropertyValue]
    ) -> [String: String] {
        first.reduce(into: [:]) { result, pair in
            guard Catalog.entry(forPublished: pair.key) != nil,
                let literal = pair.value.literal,
                second[pair.key] == pair.value
            else { return }
            result[pair.key] = literal
        }
    }

    public var keyCount: Int { displays.values.reduce(0) { $0 + $1.count } }

    /// Keys whose live value no longer matches the baseline.
    public func drift(for display: String, current: [String: PropertyValue]) -> [Difference] {
        guard let saved = displays[display] else { return [] }
        return saved.compactMap { key, literal in
            guard let expected = try? PropertyValue.parse(literal) else { return nil }
            guard let live = current[key], live != expected else { return nil }
            return Difference(key: key, baseline: expected, current: live)
        }
        .sorted { $0.key.lowercased() < $1.key.lowercased() }
    }

    public struct Difference: Sendable, Equatable {
        public let key: String
        public let baseline: PropertyValue
        public let current: PropertyValue
    }

    // MARK: Storage

    public static var currentBuild: String {
        ProcessInfo.processInfo.operatingSystemVersionString
            .replacingOccurrences(of: "Version ", with: "")
            .replacingOccurrences(of: " (Build ", with: "-")
            .replacingOccurrences(of: ")", with: "")
    }

    /// Per-build path, so an OS update cannot silently reuse a baseline from the previous driver.
    public static func defaultURL(build: String = Baseline.currentBuild) -> URL {
        let safe = build.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        return FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".config/pwmctl/baseline-\(safe).json")
    }

    public static func load(_ url: URL) throws -> Baseline {
        try JSONDecoder().decode(Baseline.self, from: Data(contentsOf: url))
    }

    public func write(to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
