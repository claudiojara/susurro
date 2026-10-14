import Foundation
import Testing

@testable import Domain

@Suite("Setting key", .timeLimit(.minutes(1)))
struct SettingKeyTests {
    /// The raw values differ from the case names, so a key that stored the case name instead would be caught.
    private enum Edge: String, Sendable {
        case top = "screen-top"
        case bottom = "screen-bottom"
    }

    private enum Level: Int, Sendable {
        case low = 0
        case high = 1
    }

    private struct Combo: Codable, Sendable, Equatable {
        var keyCode: Int
        var modifiers: [String]
    }

    private struct Unencodable: Codable, Sendable {
        init() {}
        init(from decoder: any Decoder) throws {}
        func encode(to encoder: any Encoder) throws {
            throw EncodingError.invalidValue(self, .init(codingPath: [], debugDescription: "never stored"))
        }
    }

    /// The stored form as `Any?`, which reads without the coercion warning that a cast from `(any Sendable)?` gives.
    private func encoded<Value>(_ key: SettingKey<Value>, _ value: Value) -> Any? { key.encode(value) }

    @Test("a key is stored under its name and carries its default")
    func nameAndDefault() {
        let key = SettingKey<Int>(area: "history", name: "retentionDays", default: 7)

        #expect(key.storageName == "history.retentionDays")
        #expect(key.defaultValue == 7)
    }

    @Test("a basic value is stored as itself and read back as the same value")
    func basicValuesRoundTrip() throws {
        let flag = SettingKey<Bool>(area: "general", name: "launchAtLogin", default: false)
        let count = SettingKey<Int>(area: "history", name: "retentionDays", default: 7)
        let seconds = SettingKey<Double>(area: "hotkey", name: "holdThreshold", default: 0.3)
        let text = SettingKey<String>(area: "speech", name: "language", default: "auto")

        let storedFlag = try #require(encoded(flag, true))
        let storedCount = try #require(encoded(count, 30))
        let storedSeconds = try #require(encoded(seconds, 0.45))
        let storedText = try #require(encoded(text, "es"))

        #expect(storedFlag as? Bool == true)
        #expect(flag.decode(storedFlag) == true)
        #expect(storedCount as? Int == 30)
        #expect(count.decode(storedCount) == 30)
        #expect(storedSeconds as? Double == 0.45)
        #expect(seconds.decode(storedSeconds) == 0.45)
        #expect(storedText as? String == "es")
        #expect(text.decode(storedText) == "es")
    }

    @Test("a stored value of another type is not read, and is not turned into the wanted type")
    func basicValuesRejectOtherTypes() {
        let flag = SettingKey<Bool>(area: "general", name: "launchAtLogin", default: false)
        let count = SettingKey<Int>(area: "history", name: "retentionDays", default: 7)
        let seconds = SettingKey<Double>(area: "hotkey", name: "holdThreshold", default: 0.3)
        let text = SettingKey<String>(area: "speech", name: "language", default: "auto")

        #expect(flag.decode("yes") == nil)
        #expect(count.decode("7") == nil)
        #expect(count.decode(1.5) == nil)
        #expect(seconds.decode("0.3") == nil)
        #expect(text.decode(3) == nil)
    }

    @Test("a number is read only as the kind it was stored as: a Bool, an integer and a real are three kinds")
    func numbersAreNotCoerced() {
        let flag = SettingKey<Bool>(area: "general", name: "launchAtLogin", default: false)
        let count = SettingKey<Int>(area: "history", name: "retentionDays", default: 7)
        let seconds = SettingKey<Double>(area: "hotkey", name: "holdThreshold", default: 0.3)
        let asBool = NSNumber(value: true)
        let asInt = NSNumber(value: 1)
        let asDouble = NSNumber(value: 1.0)

        #expect(flag.decode(asBool) == true)
        #expect(count.decode(asInt) == 1)
        #expect(seconds.decode(asDouble) == 1.0)
        #expect(flag.decode(asInt) == nil)
        #expect(flag.decode(asDouble) == nil)
        #expect(count.decode(asBool) == nil)
        #expect(count.decode(asDouble) == nil)
        #expect(seconds.decode(asBool) == nil)
        #expect(seconds.decode(asInt) == nil)
    }

    @Test("an enum is stored as its raw value, and a raw value that is not one of its cases is not read")
    func rawRepresentableValues() throws {
        let key = SettingKey<Edge>(area: "overlay", name: "edge", default: .bottom)

        #expect(try #require(encoded(key, .top)) as? String == "screen-top")
        #expect(key.decode("screen-top") == .top)
        #expect(key.decode("screen-bottom") == .bottom)
        #expect(key.decode("diagonal") == nil)
        #expect(key.decode("top") == nil)
        #expect(key.decode(3) == nil)
    }

    @Test("the raw value of an enum is read as strictly as a basic value")
    func rawValuesAreNotCoerced() {
        let key = SettingKey<Level>(area: "overlay", name: "level", default: .low)

        #expect(key.decode(NSNumber(value: 1)) == .high)
        #expect(key.decode(NSNumber(value: true)) == nil)
        #expect(key.decode(NSNumber(value: 1.0)) == nil)
    }

    @Test("a Codable value is stored as JSON data, and data that is not that value is not read")
    func jsonValues() throws {
        let key = SettingKey<Combo>.json(
            area: "hotkey", name: "combo", default: Combo(keyCode: 2, modifiers: ["control"]))
        let combo = Combo(keyCode: 40, modifiers: ["control", "option"])

        let stored = try #require(encoded(key, combo) as? Data)

        #expect(key.decode(stored) == combo)
        #expect(key.decode(Data("not json".utf8)) == nil)
        #expect(key.decode(Data(#"{"keyCode":"forty"}"#.utf8)) == nil)
        #expect(key.decode("{\"keyCode\":40,\"modifiers\":[]}") == nil)
    }

    @Test("a value that cannot be encoded has no stored form")
    func unencodableValue() {
        let key = SettingKey<Unencodable>.json(area: "hotkey", name: "combo", default: Unencodable())

        #expect(encoded(key, Unencodable()) == nil)
    }

    @Test(
        "a part of a key name is valid unless it is empty or has a dot, which would make two keys share a storage name",
        arguments: [
            ("hotkey", true), ("holdThreshold", true), ("launch-at-login", true), ("v2", true),
            ("", false), (".", false), ("hot.key", false), (".hotkey", false), ("hotkey.", false),
        ]
    )
    func validParts(part: String, isValid: Bool) {
        #expect(SettingKeyPart.isValid(part) == isValid)
    }

    @Test("a key with an empty part or a dot in a part cannot be declared, whichever way it is declared")
    func invalidPartsAreRefused() async {
        await #expect(processExitsWith: .failure) { _ = SettingKey<Int>(area: "", name: "retentionDays", default: 7) }
        await #expect(processExitsWith: .failure) { _ = SettingKey<Int>(area: "history", name: "", default: 7) }
        await #expect(processExitsWith: .failure) { _ = SettingKey<Bool>(area: "his.tory", name: "on", default: true) }
        await #expect(processExitsWith: .failure) {
            _ = SettingKey<Edge>(area: "overlay", name: "e.dge", default: .top)
        }
        await #expect(processExitsWith: .failure) {
            _ = SettingKey<Combo>.json(area: "hotkey", name: "", default: Combo(keyCode: 2, modifiers: []))
        }
        await #expect(processExitsWith: .success) {
            _ = SettingKey<Int>(area: "history", name: "retentionDays", default: 7)
        }
    }
}
