import Foundation
import PWMKit

// MARK: - Options

struct Options {
    var display: String?
    var json = false
    var allKeys = false
    var dryRun = false
    var force = false
    var write = false
    var revertAfter: Int?
    var revertTo: [String: PropertyValue] = [:]
    var category: PropertyCategory?
    var risk: PropertyRisk?
    var newIn: String?
    var out: String?
    var positional: [String] = []
}

enum CLIError: Error, CustomStringConvertible {
    case usage(String)
    case failure(String)
    case needsRoot(String)

    var description: String {
        switch self {
        case .usage(let message), .failure(let message), .needsRoot(let message): return message
        }
    }

    var exitCode: Int32 {
        switch self {
        case .usage: return 2
        case .failure: return 1
        case .needsRoot: return 3
        }
    }
}

let usage = """
    pwmctl - read and write IOMFB framebuffer properties (PWM / backlight / dither knobs)

    usage:
      pwmctl displays [--json]
      pwmctl get [--display NAME] [KEY...] [--all-keys] [--json]
      pwmctl set [--display NAME] KEY=VALUE... [--revert-after N] [--revert-to KEY=VALUE]
                 [--dry-run] [--force]
      pwmctl probe [--display NAME] [--write] [--json]
      pwmctl keys [--category CAT] [--risk safe|risky] [--new-in LABEL] [--json]
      pwmctl baseline save|diff|restore [--file FILE] [--display NAME] [--dry-run] [--force]
      pwmctl snapshot [--out FILE]

    values:
      true/false        boolean
      42, 0x2a          integer
      0.25q16           16.16 fixed point (65536 == 1.0)
      s:text            string

    baseline:
      save records every writable value per display to ~/.config/pwmctl/baseline-<build>.json,
      diff shows what has drifted from it, restore writes the saved values back. Save one while
      the display is known good; restore is the way out if a knob leaves something stuck.

    notes:
      Properties are runtime-only: a reboot clears everything. Writes do not need sudo on macOS 26.6
      or 27 (the driver applies them for a normal user); if it ever reports "not privileged", use
      sudo.
      --revert-after N restores the previous values after N seconds (and on ^C), so a knob that
      blacks out the panel recovers by itself. Keys marked risky require --revert-after or --force.
      A key the node does not publish yet has no previous value, so pass --revert-to KEY=VALUE to
      say what to go back to.
    """

func parse(_ arguments: [String]) throws -> (command: String, options: Options) {
    guard let command = arguments.first else { throw CLIError.usage(usage) }
    var options = Options()
    var index = 1

    func value(for flag: String) throws -> String {
        index += 1
        guard index < arguments.count else { throw CLIError.usage("\(flag) needs a value") }
        return arguments[index]
    }

    while index < arguments.count {
        let argument = arguments[index]
        switch argument {
        case "--json": options.json = true
        case "--all-keys": options.allKeys = true
        case "--dry-run": options.dryRun = true
        case "--force": options.force = true
        case "--write": options.write = true
        case "--display": options.display = try value(for: argument)
        case "--out", "--file": options.out = try value(for: argument)
        case "--new-in": options.newIn = try value(for: argument)
        case "--revert-to":
            let raw = try value(for: argument)
            let parts = raw.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else {
                throw CLIError.usage("--revert-to takes KEY=VALUE, got '\(raw)'")
            }
            do {
                options.revertTo[String(parts[0])] = try PropertyValue.parse(String(parts[1]))
            } catch let error as ValueError {
                throw CLIError.usage(error.description)
            }
        case "--revert-after":
            let raw = try value(for: argument)
            guard let seconds = Int(raw), seconds > 0, seconds <= 3600 else {
                throw CLIError.usage("--revert-after needs 1-3600 seconds, got '\(raw)'")
            }
            options.revertAfter = seconds
        case "--category":
            let raw = try value(for: argument)
            guard let category = PropertyCategory(rawValue: raw) else {
                let all = PropertyCategory.allCases.map(\.rawValue).joined(separator: ", ")
                throw CLIError.usage("unknown category '\(raw)'; expected one of: \(all)")
            }
            options.category = category
        case "--risk":
            let raw = try value(for: argument)
            guard let risk = PropertyRisk(rawValue: raw) else {
                throw CLIError.usage("unknown risk '\(raw)'; expected safe or risky")
            }
            options.risk = risk
        case "-h", "--help": throw CLIError.usage(usage)
        default:
            guard !argument.hasPrefix("-") else { throw CLIError.usage("unknown flag \(argument)") }
            options.positional.append(argument)
        }
        index += 1
    }
    return (command, options)
}

// MARK: - Output helpers

func print(error message: String) {
    FileHandle.standardError.write(Data(("pwmctl: " + message + "\n").utf8))
}

func printTable(_ rows: [[String]]) {
    guard let columns = rows.first?.count else { return }
    let widths = (0..<columns).map { column in rows.map { $0[column].count }.max() ?? 0 }
    for row in rows {
        let line = row.enumerated()
            .map { index, cell in
                index == columns - 1
                    ? cell : cell.padding(toLength: widths[index], withPad: " ", startingAt: 0)
            }
            .joined(separator: "  ")
        print(line.trimmingCharacters(in: .whitespaces).isEmpty ? "" : line)
    }
}

func emitJSON(_ value: some Encodable) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(value)
    print(String(decoding: data, as: UTF8.self))
}

struct DisplayJSON: Encodable {
    let name: String
    let className: String
    let entryID: String
    let publishedKeys: Int
}

struct PropertyJSON: Encodable {
    let key: String
    let type: String
    let value: String
    let fixedPointValue: Double?
    let category: String?
    let risk: String?
    let newIn: String?

    enum CodingKeys: String, CodingKey {
        case key, type, value, fixedPointValue, category, risk, newIn
    }

    // Emit every field, null included: omitting them makes `--json` awkward to consume.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key, forKey: .key)
        try container.encode(type, forKey: .type)
        try container.encode(value, forKey: .value)
        try container.encode(fixedPointValue, forKey: .fixedPointValue)
        try container.encode(category, forKey: .category)
        try container.encode(risk, forKey: .risk)
        try container.encode(newIn, forKey: .newIn)
    }
}

struct ProbeResultJSON: Encodable {
    let key: String
    let status: String
    let detail: String?

    enum CodingKeys: String, CodingKey { case key, status, detail }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key, forKey: .key)
        try container.encode(status, forKey: .status)
        try container.encode(detail, forKey: .detail)
    }
}

struct SnapshotJSON: Encodable {
    let generated: String
    let osVersion: String
    let displays: [String: [String: String]]
}

func propertyJSON(key: String, value: PropertyValue) -> PropertyJSON {
    let entry = Catalog.entry(forPublished: key)
    return PropertyJSON(
        key: key,
        type: value.typeName,
        value: value.describe(),
        fixedPointValue: entry?.fixedPoint == true ? value.fixedPointValue : nil,
        category: entry?.category.rawValue,
        risk: entry?.risk.rawValue,
        newIn: entry?.newIn)
}

func annotate(key: String, value: PropertyValue) -> String {
    let entry = Catalog.entry(forPublished: key)
    var line = "\(key) = \(value.describe(fixedPoint: entry?.fixedPoint ?? false))"
    var tags: [String] = []
    if let newIn = entry?.newIn { tags.append("new in \(newIn)") }
    if entry?.risk == .risky { tags.append("risky") }
    if entry == nil { tags.append("not in catalog") }
    if !tags.isEmpty { line += "  [\(tags.joined(separator: ", "))]" }
    return line
}

// MARK: - Commands

func runDisplays(_ options: Options) throws {
    let nodes = try Framebuffer.all()
    guard !nodes.isEmpty else { throw CLIError.failure("no framebuffer nodes found") }
    if options.json {
        try emitJSON(
            nodes.map { node in
                DisplayJSON(
                    name: node.name, className: node.className,
                    entryID: "0x" + String(node.entryID, radix: 16),
                    publishedKeys: (try? node.read().count) ?? 0)
            })
        return
    }
    var rows = [["NAME", "CLASS", "ENTRY ID", "KEYS", ""]]
    for node in nodes {
        let isDefault = node.name == Framebuffer.internalDisplayName
        rows.append([
            node.name, node.className, "0x" + String(node.entryID, radix: 16),
            String((try? node.read().count) ?? 0), isDefault ? "(default target)" : "",
        ])
    }
    printTable(rows)
}

func runGet(_ options: Options) throws {
    let display = try Framebuffer.resolve(options.display)
    let properties = try display.read()

    var keys: [String]
    if !options.positional.isEmpty {
        keys = options.positional
        let missing = keys.filter { properties[$0] == nil }
        if !missing.isEmpty {
            print(error: "not published by \(display.name): \(missing.joined(separator: ", "))")
        }
        keys = keys.filter { properties[$0] != nil }
    } else {
        keys = properties.keys.filter { Catalog.entry(forPublished: $0) != nil }
        if options.allKeys {
            keys += properties.keys.filter { Catalog.entry(forPublished: $0) == nil }
        }
    }

    if options.json {
        try emitJSON(keys.sorted().map { propertyJSON(key: $0, value: properties[$0]!) })
        return
    }

    print("\(display.name) (\(display.className), \(properties.count) properties published)")
    let grouped = Dictionary(grouping: keys) { Catalog.entry(forPublished: $0)?.category }
    let order: [PropertyCategory?] = PropertyCategory.allCases + [nil]
    for category in order {
        guard let members = grouped[category], !members.isEmpty else { continue }
        print("\n[\(category?.rawValue ?? "uncatalogued")]")
        for key in members.sorted(by: { $0.lowercased() < $1.lowercased() }) {
            print("  " + annotate(key: key, value: properties[key]!))
        }
    }
}

func runSet(_ options: Options) throws {
    guard !options.positional.isEmpty else {
        throw CLIError.usage("set needs at least one KEY=VALUE")
    }
    var requested: [String: PropertyValue] = [:]
    var order: [String] = []
    for argument in options.positional {
        let parts = argument.split(separator: "=", maxSplits: 1)
        guard parts.count == 2 else {
            throw CLIError.usage("expected KEY=VALUE, got '\(argument)'")
        }
        let key = String(parts[0])
        do {
            requested[key] = try PropertyValue.parse(String(parts[1]))
            order.append(key)
        } catch let error as ValueError {
            throw CLIError.usage(error.description)
        }
    }

    let risky = order.filter { Catalog.entry(forPublished: $0)?.risk == .risky }
    if !risky.isEmpty, options.revertAfter == nil, !options.force {
        throw CLIError.usage(
            "\(risky.joined(separator: ", ")) can black out the panel; "
                + "pass --revert-after N or --force")
    }
    for key in order where Catalog.entry(forPublished: key) == nil {
        print(error: "'\(key)' is not in the catalog; the driver will likely reject it")
    }

    let display = try Framebuffer.resolve(options.display)
    let before = try display.read()

    // A key can be published under a different spelling than the one typed, and it is only
    // accepted for writing under the published one. Resolve against the node before touching it.
    let resolved = Dictionary(
        uniqueKeysWithValues: order.map { typed in
            (typed, Catalog.publishedSpellings(of: typed).first { before[$0] != nil } ?? typed)
        })

    if options.dryRun {
        print("would write to \(display.name):")
        for key in order {
            let target = resolved[key]!
            let alias = target == key ? "" : " (published as \(target))"
            let current = before[target].map { $0.describe() } ?? "<unpublished>"
            print("  \(key)\(alias): \(current) -> \(requested[key]!.describe())")
        }
        return
    }

    let overrides = Dictionary(
        uniqueKeysWithValues: options.revertTo.map { (resolved[$0.key] ?? $0.key, $0.value) })
    let plan = RevertGuard.plan(
        keys: order.map { resolved[$0]! }, current: before, overrides: overrides)
    if options.revertAfter != nil, !plan.unpublished.isEmpty, !options.force {
        throw CLIError.usage(
            "cannot revert \(plan.unpublished.joined(separator: ", ")): nothing published to "
                + "restore. Give the value to go back to, e.g. --revert-to "
                + "\(plan.unpublished[0])=false, or --force to write without a way back (only a "
                + "reboot clears it)")
    }

    if !FileManager.default.fileExists(atPath: Baseline.defaultURL().path) {
        print(
            error: "no baseline for this build yet - `pwmctl baseline save` records one you can "
                + "restore later")
    }

    // One key at a time: the driver reports a single status per call, and a rejected key should not
    // hide the outcome of the others.
    var accepted: [String: String] = [:]
    var rejected = false
    var needsRoot = false
    for key in order {
        do {
            accepted[key] = try display.write(key: resolved[key]!, value: requested[key]!)
        } catch let error as FramebufferError {
            print(error: error.description)
            rejected = true
            needsRoot = needsRoot || error.needsRoot
        }
    }

    let after = try display.read()
    print("wrote to \(display.name):")
    for key in order {
        guard let target = accepted[key] else { continue }
        let alias = target == key ? "" : " (as \(target))"
        let old = before[target].map { $0.describe() } ?? "<unpublished>"
        let new = after[target].map { $0.describe() } ?? "<not published back>"
        let ignored =
            after[target] != nil && after[target] == before[target]
            && before[target] != requested[key]
        print(
            "  \(key)\(alias): \(old) -> \(new)\(ignored ? "  [unchanged: driver ignored it]" : "")"
        )
    }
    if rejected, accepted.isEmpty { exit(needsRoot ? 3 : 4) }

    guard let seconds = options.revertAfter else { return }
    if !plan.unpublished.isEmpty {
        print(
            error: "cannot restore \(plan.unpublished.joined(separator: ", ")) - reboot clears it")
    }
    let restorable = plan.restorable
    guard !restorable.isEmpty else {
        if rejected { exit(needsRoot ? 3 : 4) }
        return
    }
    print("reverting in \(seconds)s (^C reverts now)")
    fflush(stdout)  // stdout is block-buffered when piped; keep the countdown in order
    RevertGuard.hold(
        seconds: seconds,
        tick: { remaining in
            FileHandle.standardError.write(Data("\rrevert in \(remaining)s    ".utf8))
        },
        restore: {
            FileHandle.standardError.write(Data("\r".utf8))
            do {
                try display.write(restorable)
                print("reverted: " + restorable.keys.sorted().joined(separator: ", "))
            } catch {
                print(error: "revert failed: \(error) - reboot to clear")
            }
        })
    if rejected { exit(needsRoot ? 3 : 4) }
}

func runProbe(_ options: Options) throws {
    let display = try Framebuffer.resolve(options.display)
    let properties = try display.read()
    let candidates: [(entry: CatalogEntry, published: String, value: PropertyValue)] =
        Catalog.entries
        .compactMap { entry in
            for spelling in Catalog.publishedSpellings(of: entry.key) {
                if let value = properties[spelling], value.isWritable {
                    return (entry, spelling, value)
                }
            }
            return nil
        }
        .sorted { $0.entry.key.lowercased() < $1.entry.key.lowercased() }
    let unpublished = Catalog.entries.count - candidates.count

    guard options.write else {
        print(
            "\(display.name): \(candidates.count) of \(Catalog.entries.count) catalogued keys are "
                + "published and writable\n\(unpublished) have no published value, so a no-op "
                + "write cannot test them")
        print("pass --write to rewrite each published value unchanged and record the status")
        if !options.json {
            for candidate in candidates {
                let alias =
                    candidate.published == candidate.entry.key
                    ? "" : " (published as \(candidate.published))"
                let value = candidate.value.describe(fixedPoint: candidate.entry.fixedPoint)
                print("  \(candidate.entry.key) = \(value)\(alias)")
            }
        }
        return
    }

    var results: [ProbeResultJSON] = []
    for candidate in candidates {
        do {
            let used = try display.write(key: candidate.published, value: candidate.value)
            let detail = used == candidate.entry.key ? nil : "as \(used)"
            results.append(
                ProbeResultJSON(key: candidate.entry.key, status: "accepted", detail: detail))
        } catch let error as FramebufferError {
            let detail = error.code.map { FramebufferError.describe($0) }
            results.append(
                ProbeResultJSON(key: candidate.entry.key, status: "rejected", detail: detail))
        }
    }

    if options.json {
        try emitJSON(results)
        return
    }
    let accepted = results.filter { $0.status == "accepted" }
    print("\(display.name): \(accepted.count) accepted, \(results.count - accepted.count) rejected")
    for result in results {
        let suffix = result.detail.map { " - \($0)" } ?? ""
        print("  \(result.status == "accepted" ? "ok  " : "fail") \(result.key)\(suffix)")
    }
}

func runKeys(_ options: Options) throws {
    let entries = Catalog.filter(
        category: options.category, risk: options.risk, newIn: options.newIn)
    guard !entries.isEmpty else { throw CLIError.failure("no catalogued keys match those filters") }
    if options.json {
        try emitJSON(entries.sorted { $0.key.lowercased() < $1.key.lowercased() })
        return
    }
    var rows = [["KEY", "CATEGORY", "RISK", "NEW IN", "FORMAT"]]
    for entry in entries.sorted(by: { $0.key.lowercased() < $1.key.lowercased() }) {
        rows.append([
            entry.key, entry.category.rawValue, entry.risk.rawValue, entry.newIn ?? "-",
            entry.fixedPoint ? "16.16" : "-",
        ])
    }
    printTable(rows)
    print("\n\(entries.count) of \(Catalog.entries.count) catalogued keys")
}

func runSnapshot(_ options: Options) throws {
    var displays: [String: [String: String]] = [:]
    for node in try Framebuffer.all() {
        let properties = try node.read()
        displays[node.name] = properties.reduce(into: [:]) { result, pair in
            guard case .unsupported = pair.value else {
                result[pair.key] = pair.value.describe()
                return
            }
        }
    }
    let snapshot = SnapshotJSON(
        generated: ISO8601DateFormatter().string(from: Date()),
        osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
        displays: displays)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(snapshot)
    if let path = options.out {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        print("wrote \(path)")
    } else {
        print(String(decoding: data, as: UTF8.self))
    }
}

struct DifferenceJSON: Encodable {
    let display: String
    let key: String
    let baseline: String
    let current: String
}

func runBaseline(_ options: Options) throws {
    let url = options.out.map { URL(fileURLWithPath: $0) } ?? Baseline.defaultURL()
    switch options.positional.first {
    case "save":
        if FileManager.default.fileExists(atPath: url.path), !options.force {
            throw CLIError.failure(
                "\(url.path) exists; pass --force to overwrite - do not replace a good baseline "
                    + "with a stuck state")
        }
        let baseline = try Baseline.capture(try Framebuffer.all())
        try baseline.write(to: url)
        print(
            "saved \(baseline.keyCount) values across \(baseline.displays.count) displays "
                + "(build \(baseline.build)) to \(url.path)")

    case "diff", nil:
        let baseline = try loadBaseline(url)
        var all: [DifferenceJSON] = []
        for node in try Framebuffer.all() where baseline.displays[node.name] != nil {
            if let selector = options.display, node.name != selector { continue }
            for difference in baseline.drift(for: node.name, current: try node.read()) {
                all.append(
                    DifferenceJSON(
                        display: node.name, key: difference.key,
                        baseline: difference.baseline.describe(),
                        current: difference.current.describe()))
            }
        }
        if options.json {
            try emitJSON(all)
            return
        }
        print("baseline \(url.lastPathComponent), captured \(baseline.captured)")
        guard !all.isEmpty else {
            print("no drift: every saved value matches")
            return
        }
        for difference in all {
            print(
                "  \(difference.display) \(difference.key): \(difference.baseline) -> "
                    + "\(difference.current)")
        }
        print("\n\(all.count) value(s) differ; `pwmctl baseline restore` puts them back")

    case "restore":
        let baseline = try loadBaseline(url)
        var restored = 0
        var failed = 0
        for node in try Framebuffer.all() where baseline.displays[node.name] != nil {
            if let selector = options.display, node.name != selector { continue }
            let drift = baseline.drift(for: node.name, current: try node.read())
            guard !drift.isEmpty else {
                print("\(node.name): matches baseline")
                continue
            }
            for difference in drift {
                let target = "\(node.name) \(difference.key)"
                if options.dryRun {
                    print(
                        "  would restore \(target): \(difference.current.describe()) -> "
                            + "\(difference.baseline.describe())")
                    continue
                }
                do {
                    try node.write(key: difference.key, value: difference.baseline)
                    print(
                        "  restored \(target): \(difference.current.describe()) -> "
                            + "\(difference.baseline.describe())")
                    restored += 1
                } catch let error as FramebufferError {
                    print(error: "cannot restore \(target): \(error.description)")
                    failed += 1
                }
            }
        }
        if !options.dryRun { print("restored \(restored), failed \(failed)") }
        if failed > 0 { exit(4) }

    case .some(let verb):
        throw CLIError.usage("baseline takes save, diff or restore, not '\(verb)'")
    }
}

func loadBaseline(_ url: URL) throws -> Baseline {
    do {
        return try Baseline.load(url)
    } catch {
        throw CLIError.failure(
            "cannot read \(url.path): \(error.localizedDescription). "
                + "Run `pwmctl baseline save` first")
    }
}

// MARK: - Entry point

func main() {
    do {
        let (command, options) = try parse(Array(CommandLine.arguments.dropFirst()))
        switch command {
        case "displays": try runDisplays(options)
        case "get": try runGet(options)
        case "set": try runSet(options)
        case "probe": try runProbe(options)
        case "keys": try runKeys(options)
        case "snapshot": try runSnapshot(options)
        case "baseline": try runBaseline(options)
        case "help": print(usage)
        default: throw CLIError.usage("unknown command '\(command)'\n\n\(usage)")
        }
    } catch let error as CLIError {
        if case .usage(let message) = error, message == usage {
            print(usage)
            exit(0)
        }
        print(error: error.description)
        exit(error.exitCode)
    } catch let error as FramebufferError {
        print(error: error.description)
        exit(error.needsRoot ? 3 : 1)
    } catch {
        print(error: "\(error)")
        exit(1)
    }
}

main()
