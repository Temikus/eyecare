import Testing

@testable import PWMKit

@Suite("Generated catalog")
struct CatalogTests {
    @Test("the generated catalog is populated and unique")
    func shape() {
        #expect(Catalog.entries.count > 250)
        #expect(Set(Catalog.entries.map(\.key)).count == Catalog.entries.count)
        #expect(Catalog.entry(for: "definitelyNotAnIOMFBKey") == nil)
    }

    @Test(
        "the two long-known knobs are safe dimming keys",
        arguments: ["enableDither", "uniformity2D"])
    func knownKnobs(key: String) throws {
        let entry = try #require(Catalog.entry(for: key))
        #expect(entry.category == .dimming)
        #expect(entry.risk == .safe)
        #expect(entry.newIn == nil)
    }

    @Test("macOS 27 additions are tagged")
    func newKeys() {
        let added = Catalog.filter(newIn: "27").map(\.key)
        #expect(added.contains("enableHBLD"))
        #expect(added.contains("HBLDDimmingFactorMin"))
        #expect(added.contains("DBVValue"))
        #expect(added.count > 20)
    }

    @Test(
        "keys that drive brightness registers are flagged risky",
        arguments: ["DBVValue", "BLMVLEDManual", "digitalDimmingLevel"])
    func riskyKeys(key: String) throws {
        #expect(try #require(Catalog.entry(for: key)).risk == .risky)
    }

    @Test("16.16 keys are flagged so values print scaled")
    func fixedPointKeys() throws {
        #expect(try #require(Catalog.entry(for: "HBLDDimmingFactorMin")).fixedPoint)
        #expect(try #require(Catalog.entry(for: "digitalDimmingLevel")).fixedPoint)
        #expect(try #require(Catalog.entry(for: "enableDither")).fixedPoint == false)
    }

    @Test("filters compose")
    func filters() {
        let riskyDimming = Catalog.filter(category: .dimming, risk: .risky)
        #expect(!riskyDimming.isEmpty)
        #expect(riskyDimming.allSatisfy { $0.category == .dimming && $0.risk == .risky })
        #expect(Catalog.filter(category: .refresh).allSatisfy { $0.category == .refresh })
    }
}

@Suite("Published key spellings")
struct CatalogAliasTests {
    /// digitalDimmingLevel is written under that name but reads back as IOMFBDigitalDimmingLevel.
    @Test(
        "IOMFB-prefixed published keys resolve to their runtime property",
        arguments: [
            ("IOMFBDigitalDimmingLevel", "digitalDimmingLevel"),
            ("IOMFBBrightnessLevel", "brightnessLevel"),
            ("enableDither", "enableDither"),
        ])
    func resolvesPrefix(published: String, expected: String) throws {
        #expect(try #require(Catalog.entry(forPublished: published)).key == expected)
    }

    @Test("unknown keys stay unknown under both spellings")
    func unknown() {
        #expect(Catalog.entry(forPublished: "IOMFBNotARealKey") == nil)
        #expect(Catalog.entry(forPublished: "IOMFB") == nil)
    }

    @Test("both spellings are offered when looking for a published value")
    func spellings() {
        #expect(
            Catalog.publishedSpellings(of: "digitalDimmingLevel")
                == ["digitalDimmingLevel", "IOMFBDigitalDimmingLevel"])
    }
}
