import Foundation
import IOKit

/// An IOMFB framebuffer node: the internal panel (`disp0`), an external pipe (`dispext0`) or the
/// Touch Bar (`dispdfr`).
public final class Framebuffer: @unchecked Sendable {
    /// Classes that carry the runtime properties. AppleCLCD2 drives display pipes,
    /// AppleMobileADBE0 the Touch Bar.
    public static let classNames = ["AppleCLCD2", "AppleMobileADBE0"]
    /// The built-in panel, and so the default target.
    public static let internalDisplayName = "disp0"

    public let name: String
    public let className: String
    public let entryID: UInt64
    private let service: io_object_t

    init(service: io_object_t, className: String) {
        self.service = service
        self.className = className
        var id: UInt64 = 0
        IORegistryEntryGetRegistryEntryID(service, &id)
        entryID = id
        name = Self.nodeName(of: service)
    }

    deinit { IOObjectRelease(service) }

    public static func all() throws -> [Framebuffer] {
        var found: [Framebuffer] = []
        for className in classNames {
            var iterator: io_iterator_t = 0
            let result = IOServiceGetMatchingServices(
                kIOMainPortDefault, IOServiceMatching(className), &iterator)
            guard result == KERN_SUCCESS else {
                throw FramebufferError("cannot match \(className)", code: result)
            }
            defer { IOObjectRelease(iterator) }
            while case let service = IOIteratorNext(iterator), service != 0 {
                found.append(Framebuffer(service: service, className: className))
            }
        }
        return found.sorted { $0.name < $1.name }
    }

    public static var isAvailable: Bool { ((try? all()) ?? []).isEmpty == false }

    /// Resolves a `--display` selector, defaulting to the internal panel.
    public static func resolve(_ selector: String?) throws -> Framebuffer {
        let nodes = try all()
        guard !nodes.isEmpty else {
            throw FramebufferError(
                "no framebuffer nodes found (expected \(classNames.joined(separator: " or ")))")
        }
        guard let selector else {
            return nodes.first { $0.name == internalDisplayName } ?? nodes[0]
        }
        guard let match = nodes.first(where: { $0.name == selector }) else {
            let names = nodes.map(\.name).joined(separator: ", ")
            throw FramebufferError("no display named '\(selector)'; available: \(names)")
        }
        return match
    }

    // MARK: Properties

    public func read() throws -> [String: PropertyValue] {
        var unmanaged: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0)
        guard result == KERN_SUCCESS, let raw = unmanaged?.takeRetainedValue() as NSDictionary?
        else {
            throw FramebufferError("cannot read properties of \(name)", code: result)
        }
        var properties: [String: PropertyValue] = [:]
        for (key, value) in raw {
            guard let key = key as? String else { continue }
            properties[key] = PropertyValue.from(value)
        }
        return properties
    }

    /// Writes properties to the live driver. Requires root; the driver reports one status for the
    /// whole batch, so callers wanting per-key results should write one key at a time.
    public func write(_ values: [String: PropertyValue]) throws {
        var payload: [String: Any] = [:]
        for (key, value) in values {
            guard let cfValue = value.cfValue else {
                throw FramebufferError("cannot write \(value.typeName) values (key '\(key)')")
            }
            payload[key] = cfValue
        }
        let result = IORegistryEntrySetCFProperties(service, payload as CFDictionary)
        guard result == KERN_SUCCESS else {
            let keys = values.keys.sorted().joined(separator: ", ")
            throw FramebufferError("\(name) rejected write of \(keys)", code: result)
        }
    }

    /// Writes one property, trying each spelling it may be known by. Keys published with an IOMFB
    /// prefix are only accepted under that prefix, and unpublished keys could go either way, so the
    /// accepted spelling is returned rather than assumed.
    @discardableResult
    public func write(key: String, value: PropertyValue) throws -> String {
        var failure: Error?
        for spelling in Catalog.publishedSpellings(of: key) {
            do {
                try write([spelling: value])
                return spelling
            } catch {
                failure = failure ?? error
            }
        }
        throw failure ?? FramebufferError("cannot write \(key)")
    }

    private static func nodeName(of service: io_object_t) -> String {
        // IONameMatched looks like "disp0,t8112"; the part before the comma is the node.
        if let matched = IORegistryEntryCreateCFProperty(
            service, "IONameMatched" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String,
            let node = matched.split(separator: ",").first
        {
            return String(node)
        }
        var buffer = [CChar](repeating: 0, count: 128)  // io_name_t
        guard IORegistryEntryGetName(service, &buffer) == KERN_SUCCESS else { return "unknown" }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}

public struct FramebufferError: Error, CustomStringConvertible {
    public let message: String
    public let code: kern_return_t?

    public init(_ message: String, code: kern_return_t? = nil) {
        self.message = message
        self.code = code
    }

    public var needsRoot: Bool { code == kIOReturnNotPrivileged }

    public var description: String {
        guard let code else { return message }
        return "\(message): \(Self.describe(code))"
    }

    public static func describe(_ code: kern_return_t) -> String {
        let name: String
        switch code {
        case kIOReturnSuccess: name = "success"
        case kIOReturnNotPrivileged: name = "not privileged (run with sudo)"
        case kIOReturnUnsupported: name = "unsupported (driver does not take this key)"
        case kIOReturnBadArgument: name = "bad argument (wrong value type?)"
        case kIOReturnNotPermitted: name = "not permitted"
        case kIOReturnNotFound: name = "not found"
        case kIOReturnNoDevice: name = "no device"
        case kIOReturnInternalError: name = "internal error"
        case kIOReturnError: name = "general error"
        default: name = "IOReturn"
        }
        return "\(name) (0x\(String(UInt32(bitPattern: code), radix: 16)))"
    }
}
