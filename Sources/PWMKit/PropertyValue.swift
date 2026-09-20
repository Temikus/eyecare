import CoreFoundation
import Foundation

/// A scalar IORegistry property value, in the shapes IOMFB actually uses.
public enum PropertyValue: Equatable, Sendable {
    case bool(Bool)
    case int(Int64)
    case string(String)
    case data(byteCount: Int)
    /// Dictionaries, arrays and anything else we neither display nor write.
    case unsupported(String)

    public static let fixedPointScale = 65536.0

    // MARK: Parsing

    /// Parses a command-line value. `q16` suffix means 16.16 fixed point (`0.25q16` -> 16384),
    /// `s:` prefix forces a string.
    public static func parse(_ text: String) throws -> PropertyValue {
        switch text.lowercased() {
        case "true", "yes", "on": return .bool(true)
        case "false", "no", "off": return .bool(false)
        default: break
        }
        if text.hasPrefix("s:") { return .string(String(text.dropFirst(2))) }

        let lowered = text.lowercased()
        if lowered.hasSuffix("q16") {
            let body = String(lowered.dropLast(3))
            guard let scalar = Double(body), scalar.isFinite else {
                throw ValueError.unparsable(text)
            }
            let scaled = (scalar * fixedPointScale).rounded()
            guard scaled >= Double(Int32.min), scaled <= Double(Int32.max) else {
                throw ValueError.outOfRange(text)
            }
            return .int(Int64(scaled))
        }
        let negative = lowered.hasPrefix("-")
        let magnitude = negative ? String(lowered.dropFirst()) : lowered
        if magnitude.hasPrefix("0x") {
            guard let parsed = Int64(magnitude.dropFirst(2), radix: 16) else {
                throw ValueError.unparsable(text)
            }
            return .int(negative ? -parsed : parsed)
        }
        if let parsed = Int64(text) { return .int(parsed) }
        throw ValueError.unparsable(text)
    }

    // MARK: Display

    public var typeName: String {
        switch self {
        case .bool: return "bool"
        case .int: return "int"
        case .string: return "string"
        case .data: return "data"
        case .unsupported(let type): return type
        }
    }

    public func describe(fixedPoint: Bool = false) -> String {
        switch self {
        case .bool(let flag): return flag ? "true" : "false"
        case .int(let value):
            guard fixedPoint else { return String(value) }
            let scaled = Double(value) / Self.fixedPointScale
            return "\(value) (\(String(format: "%.4f", scaled)) q16)"
        case .string(let text): return "\"\(text)\""
        case .data(let byteCount): return "<\(byteCount) bytes>"
        case .unsupported(let type): return "<\(type)>"
        }
    }

    /// Fixed-point reading, for JSON output.
    public var fixedPointValue: Double? {
        guard case .int(let value) = self else { return nil }
        return Double(value) / Self.fixedPointScale
    }

    // MARK: CoreFoundation bridging

    public var isWritable: Bool { cfValue != nil }

    /// A literal `parse` accepts again, so a saved baseline stays human-editable.
    public var literal: String? {
        switch self {
        case .bool(let flag): return flag ? "true" : "false"
        case .int(let value): return String(value)
        case .string(let text): return "s:" + text
        case .data, .unsupported: return nil
        }
    }

    public var cfValue: CFTypeRef? {
        switch self {
        case .bool(let flag): return flag ? kCFBooleanTrue : kCFBooleanFalse
        case .int(let value): return NSNumber(value: value)
        case .string(let text): return text as CFString
        case .data, .unsupported: return nil
        }
    }

    public static func from(_ value: Any) -> PropertyValue {
        let reference = value as CFTypeRef
        let typeID = CFGetTypeID(reference)
        if typeID == CFBooleanGetTypeID() {
            return .bool(CFBooleanGetValue((reference as! CFBoolean)))
        }
        if typeID == CFNumberGetTypeID(), let number = value as? NSNumber {
            return .int(number.int64Value)
        }
        if let text = value as? String { return .string(text) }
        if let data = value as? Data { return .data(byteCount: data.count) }
        return .unsupported((CFCopyTypeIDDescription(typeID) as String?) ?? "unknown")
    }
}

public enum ValueError: Error, CustomStringConvertible, Equatable {
    case unparsable(String)
    case outOfRange(String)

    public var description: String {
        switch self {
        case .unparsable(let text):
            return "cannot parse '\(text)': expected true/false, an integer, 0x hex, "
                + "a 16.16 value like 0.25q16, or s:some-string"
        case .outOfRange(let text): return "'\(text)' is out of range for a 16.16 fixed-point value"
        }
    }
}
