import Foundation
import Testing

@testable import PWMKit

/// Integration against the real IOKit registry, no root needed: reads, plus one no-op write of a
/// value the panel already holds. IOMFB property names and types are undocumented and shift
/// between macOS releases, so this is the canary for a rename: a suite with a stubbed registry
/// would keep passing while the tool broke.
private let hasInternalPanel = ((try? Framebuffer.all()) ?? [])
    .contains { $0.name == Framebuffer.internalDisplayName }
private let runningAsRoot = geteuid() == 0

@Suite("Live IOMFB nodes", .enabled(if: hasInternalPanel))
struct FramebufferLiveTests {
    @Test("discovery finds display pipes and defaults to the internal panel")
    func discovery() throws {
        let nodes = try Framebuffer.all()
        #expect(nodes.contains { $0.className == "AppleCLCD2" })
        #expect(nodes.allSatisfy { $0.entryID != 0 })

        let resolved = try Framebuffer.resolve(nil)
        #expect(resolved.name == Framebuffer.internalDisplayName)
        #expect(resolved.className == "AppleCLCD2")
    }

    @Test("an unknown selector lists what is available")
    func unknownSelector() {
        #expect(throws: FramebufferError.self) { try Framebuffer.resolve("nope0") }
    }

    @Test(
        "dither and uniformity are published as booleans",
        arguments: ["enableDither", "uniformity2D"])
    func knobTypes(key: String) throws {
        let value = try #require(try Framebuffer.resolve(nil).read()[key], "\(key) is gone")
        guard case .bool = value else {
            Issue.record("\(key) is \(value.typeName), expected bool")
            return
        }
    }

    @Test("backlight modulation mode is published as an integer")
    func backlightTypes() throws {
        let value = try #require(
            try Framebuffer.resolve(nil).read()["BLMAHMode"], "BLMAHMode is gone")
        guard case .int = value else {
            Issue.record("BLMAHMode is \(value.typeName), expected int")
            return
        }
    }

    @Test("every catalogued key the panel publishes is printable")
    func catalogueCoverage() throws {
        let properties = try Framebuffer.resolve(nil).read()
        let catalogued = properties.filter { Catalog.entry(for: $0.key) != nil }
        #expect(catalogued.count > 10)
        for (key, value) in catalogued {
            #expect(!value.describe().isEmpty, "\(key) has no printable description")
        }
    }

    /// Rewriting the value the panel already holds, so nothing changes either way. IOMFB accepts
    /// this unprivileged, which is why the CLI attempts writes instead of gating on root; whether
    /// an unprivileged write is *applied* is a separate question the read-back answers.
    @Test(
        "a no-op write of a published value is accepted without root", .enabled(if: !runningAsRoot))
    func noOpWriteIsAccepted() throws {
        let panel = try Framebuffer.resolve(nil)
        let current = try #require(panel.read()["enableDither"])
        #expect(throws: Never.self) { try panel.write(["enableDither": current]) }
        #expect(try panel.read()["enableDither"] == current)
    }
}
