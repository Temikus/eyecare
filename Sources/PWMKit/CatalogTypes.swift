/// Known IOMFB runtime-property keys, generated from the kernel collection.
///
/// The key table itself lives in the generated `Catalog.swift`.
public enum Catalog {
    private static let index: [String: CatalogEntry] = Dictionary(
        entries.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })

    public static func entry(for key: String) -> CatalogEntry? { index[key] }

    /// Looks up a key as `ioreg` prints it. Some runtime properties are published with an IOMFB
    /// prefix - `digitalDimmingLevel` reads back as `IOMFBDigitalDimmingLevel` - so both spellings
    /// resolve to the same entry.
    public static func entry(forPublished key: String) -> CatalogEntry? {
        if let entry = index[key] { return entry }
        guard key.hasPrefix("IOMFB") else { return nil }
        let tail = key.dropFirst("IOMFB".count)
        guard let first = tail.first else { return nil }
        return index[first.lowercased() + tail.dropFirst()]
    }

    /// The spellings a key may appear under, the one given first. Works in both directions, since
    /// callers may hold either the runtime property name or the name ioreg prints.
    public static func publishedSpellings(of key: String) -> [String] {
        if key.hasPrefix("IOMFB") {
            let tail = key.dropFirst("IOMFB".count)
            guard let first = tail.first else { return [key] }
            return [key, first.lowercased() + tail.dropFirst()]
        }
        guard let first = key.first else { return [key] }
        return [key, "IOMFB" + first.uppercased() + key.dropFirst()]
    }

    public static func filter(
        category: PropertyCategory? = nil, risk: PropertyRisk? = nil, newIn: String? = nil
    ) -> [CatalogEntry] {
        entries.filter { entry in
            (category == nil || entry.category == category)
                && (risk == nil || entry.risk == risk)
                && (newIn == nil || entry.newIn == newIn)
        }
    }
}

public struct CatalogEntry: Sendable, Codable {
    public let key: String
    public let category: PropertyCategory
    public let risk: PropertyRisk
    /// Stored by IOMFB as 16.16 fixed point, so 65536 reads as 1.0.
    public let fixedPoint: Bool
    /// OS label that introduced the key, e.g. "27"; nil if it predates the baseline.
    public let newIn: String?

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key, forKey: .key)
        try container.encode(category, forKey: .category)
        try container.encode(risk, forKey: .risk)
        try container.encode(fixedPoint, forKey: .fixedPoint)
        try container.encode(newIn, forKey: .newIn)
    }

    public init(
        key: String, category: PropertyCategory, risk: PropertyRisk, fixedPoint: Bool,
        newIn: String?
    ) {
        self.key = key
        self.category = category
        self.risk = risk
        self.fixedPoint = fixedPoint
        self.newIn = newIn
    }
}

public enum PropertyCategory: String, CaseIterable, Sendable, Codable {
    case dimming, refresh, color, thermal, power, other
}

public enum PropertyRisk: String, CaseIterable, Sendable, Codable {
    /// Drives a panel brightness register directly: a bad value can leave the panel dark.
    case risky
    case safe
}
