import Foundation
import Testing

@testable import PWMKit

@Suite("Revert guard")
struct RevertGuardTests {
    @Test("the plan separates restorable keys from ones with nothing to restore")
    func plan() {
        let current: [String: PropertyValue] = [
            "enableDither": .bool(false),
            "BLMAHMode": .int(2),
            "DBV2NitsTable": .data(byteCount: 512),
        ]
        let plan = RevertGuard.plan(
            keys: ["enableDither", "BLMAHMode", "enableHBLD", "DBV2NitsTable"], current: current)

        #expect(plan.restorable == ["enableDither": .bool(false), "BLMAHMode": .int(2)])
        // enableHBLD publishes no value; DBV2NitsTable is data, which we cannot write back.
        #expect(plan.unpublished == ["DBV2NitsTable", "enableHBLD"])
    }

    /// A key the node does not publish has no prior value, so the caller names what to go back to.
    @Test("an override supplies the restore value for an unpublished key")
    func planWithOverrides() {
        let current: [String: PropertyValue] = ["enableDither": .bool(false)]
        let plan = RevertGuard.plan(
            keys: ["enableDither", "enableHBLD", "HBLDDimmingFactorMin"], current: current,
            overrides: ["enableHBLD": .bool(false)])

        #expect(plan.restorable == ["enableDither": .bool(false), "enableHBLD": .bool(false)])
        #expect(plan.unpublished == ["HBLDDimmingFactorMin"])
    }

    @Test("an override wins over the published value")
    func overrideBeatsCurrent() {
        let plan = RevertGuard.plan(
            keys: ["BLMAHMode"], current: ["BLMAHMode": .int(2)],
            overrides: ["BLMAHMode": .int(0)])
        #expect(plan.restorable == ["BLMAHMode": .int(0)])
        #expect(plan.unpublished.isEmpty)
    }

    @Test("hold counts down, then restores")
    func holdRestores() {
        final class Flag: @unchecked Sendable { var raised = false }
        let restored = Flag()
        var ticks: [Int] = []

        RevertGuard.hold(
            seconds: 1, tick: { ticks.append($0) }, restore: { restored.raised = true })

        #expect(ticks == [1])
        #expect(restored.raised)
    }
}

@Suite("Baseline")
struct BaselineTests {
    /// The ambient light level changes between reads, so it must not be treated as a setting.
    @Test("only catalogued, writable, stable values are recorded")
    func stableSettings() {
        let first: [String: PropertyValue] = [
            "enableDither": .bool(false),
            "BLMAHMode": .int(2),
            "AmbientBrightness": .int(158_955_664),
            "DBV2NitsTable": .data(byteCount: 512),
            "displayOnTimestamp": .int(824_773_012_292),
        ]
        var second = first
        second["AmbientBrightness"] = .int(197_778_896)

        let recorded = Baseline.stableSettings(first: first, second: second)

        #expect(recorded == ["enableDither": "false", "BLMAHMode": "2"])
        #expect(recorded["AmbientBrightness"] == nil)  // moved between reads
        #expect(recorded["DBV2NitsTable"] == nil)  // data, cannot be written back
        #expect(recorded["displayOnTimestamp"] == nil)  // not a runtime property
    }

    @Test("drift compares the saved literal against the live value")
    func drift() {
        let baseline = Baseline(
            build: "27.0-26A428", captured: "2026-09-19T00:00:00Z",
            displays: ["disp0": ["enableDither": "false", "BLMAHMode": "2"]])

        let clean = baseline.drift(
            for: "disp0", current: ["enableDither": .bool(false), "BLMAHMode": .int(2)])
        #expect(clean.isEmpty)

        let drifted = baseline.drift(
            for: "disp0", current: ["enableDither": .bool(true), "BLMAHMode": .int(2)])
        #expect(
            drifted == [
                Baseline.Difference(
                    key: "enableDither", baseline: .bool(false), current: .bool(true))
            ])
        #expect(baseline.drift(for: "dispext0", current: [:]).isEmpty)
    }

    @Test("baseline round-trips through JSON")
    func roundTrip() throws {
        let baseline = Baseline(
            build: "27.0-26A428", captured: "2026-09-19T00:00:00Z",
            displays: ["disp0": ["enableDither": "false"]])
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "pwmctl-baseline-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        try baseline.write(to: url)
        let loaded = try Baseline.load(url)
        #expect(loaded.displays == baseline.displays)
        #expect(loaded.build == baseline.build)
        #expect(loaded.keyCount == 1)
    }
}
