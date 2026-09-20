import Testing

@testable import PWMKit

@Suite("Value parsing")
struct PropertyValueTests {
    @Test(
        "booleans accept the spellings ioreg prints",
        arguments: [
            ("true", true), ("yes", true), ("on", true), ("TRUE", true), ("Yes", true),
            ("false", false), ("no", false), ("off", false), ("NO", false),
        ])
    func booleans(text: String, expected: Bool) throws {
        #expect(try PropertyValue.parse(text) == .bool(expected))
    }

    @Test("integers, decimal and hex, signed")
    func integers() throws {
        #expect(try PropertyValue.parse("2") == .int(2))
        #expect(try PropertyValue.parse("289984") == .int(289_984))
        #expect(try PropertyValue.parse("0x1a") == .int(26))
        #expect(try PropertyValue.parse("-0x10") == .int(-16))
        #expect(try PropertyValue.parse("-1") == .int(-1))
    }

    @Test("16.16 fixed point scales by 65536")
    func fixedPoint() throws {
        #expect(try PropertyValue.parse("1.0q16") == .int(65_536))
        #expect(try PropertyValue.parse("0.25q16") == .int(16_384))
        #expect(try PropertyValue.parse("0q16") == .int(0))
        // The live digital dimming level, round-tripped.
        #expect(try PropertyValue.parse("4.4248q16") == .int(289_984))
    }

    /// Bare text must not parse: sending a string where the driver wants a number buys a silent
    /// rejection instead of an error.
    @Test("strings need the s: prefix", arguments: ["disp0", "", "1.5", "0xzz"])
    func rejectsBareText(text: String) {
        #expect(throws: ValueError.self) { try PropertyValue.parse(text) }
    }

    @Test("the s: prefix keeps a string a string")
    func strings() throws {
        #expect(try PropertyValue.parse("s:disp0") == .string("disp0"))
    }

    @Test("a 16.16 value too large for the register is rejected")
    func fixedPointRange() {
        #expect(throws: ValueError.outOfRange("100000q16")) { try PropertyValue.parse("100000q16") }
        #expect(throws: ValueError.unparsable("xq16")) { try PropertyValue.parse("xq16") }
    }

    @Test("fixed-point display shows the register and the scaled reading")
    func describes() {
        #expect(PropertyValue.int(289_984).describe(fixedPoint: true) == "289984 (4.4248 q16)")
        #expect(PropertyValue.int(289_984).describe() == "289984")
        #expect(PropertyValue.bool(false).describe() == "false")
        #expect(PropertyValue.data(byteCount: 96).describe() == "<96 bytes>")
        #expect(PropertyValue.int(65_536).fixedPointValue == 1.0)
    }

    @Test("only scalars can go back to the driver")
    func writability() {
        #expect(PropertyValue.bool(true).isWritable)
        #expect(PropertyValue.int(1).isWritable)
        #expect(PropertyValue.string("x").isWritable)
        #expect(!PropertyValue.data(byteCount: 4).isWritable)
        #expect(!PropertyValue.unsupported("CFDictionary").isWritable)
    }

    @Test(
        "CoreFoundation round trip preserves the type",
        arguments: [
            PropertyValue.bool(true), .bool(false), .int(-7), .int(289_984), .string("hi"),
        ])
    func cfRoundTrip(value: PropertyValue) throws {
        let reference = try #require(value.cfValue)
        #expect(PropertyValue.from(reference) == value)
    }
}
