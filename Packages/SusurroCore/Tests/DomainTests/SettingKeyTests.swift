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
        let key = SettingKey<Int>("history.retentionDays", default: 7)

        #expect(key.storageName == "history.retentionDays")
        #expect(key.defaultValue == 7)
    }

    @Test("a basic value is stored as itself and read back as the same value")
    func basicValuesRoundTrip() throws {
        let flag = SettingKey<Bool>("general.launchAtLogin", default: false)
        let count = SettingKey<Int>("history.retentionDays", default: 7)
        let seconds = SettingKey<Double>("hotkey.holdThreshold", default: 0.3)
        let text = SettingKey<String>("speech.language", default: "auto")

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
        let flag = SettingKey<Bool>("general.launchAtLogin", default: false)
        let count = SettingKey<Int>("history.retentionDays", default: 7)
        let seconds = SettingKey<Double>("hotkey.holdThreshold", default: 0.3)
        let text = SettingKey<String>("speech.language", default: "auto")

        #expect(flag.decode("yes") == nil)
        #expect(count.decode("7") == nil)
        #expect(count.decode(1.5) == nil)
        #expect(seconds.decode("0.3") == nil)
        #expect(text.decode(3) == nil)
    }

    @Test("an enum is stored as its raw value, and a raw value that is not one of its cases is not read")
    func rawRepresentableValues() throws {
        let key = SettingKey<Edge>("overlay.edge", default: .bottom)

        #expect(try #require(encoded(key, .top)) as? String == "screen-top")
        #expect(key.decode("screen-top") == .top)
        #expect(key.decode("screen-bottom") == .bottom)
        #expect(key.decode("diagonal") == nil)
        #expect(key.decode("top") == nil)
        #expect(key.decode(3) == nil)
    }

    @Test("a Codable value is stored as JSON data, and data that is not that value is not read")
    func jsonValues() throws {
        let key = SettingKey<Combo>.json("hotkey.combo", default: Combo(keyCode: 2, modifiers: ["control"]))
        let combo = Combo(keyCode: 40, modifiers: ["control", "option"])

        let stored = try #require(encoded(key, combo) as? Data)

        #expect(key.decode(stored) == combo)
        #expect(key.decode(Data("not json".utf8)) == nil)
        #expect(key.decode(Data(#"{"keyCode":"forty"}"#.utf8)) == nil)
        #expect(key.decode("{\"keyCode\":40,\"modifiers\":[]}") == nil)
    }

    @Test("a value that cannot be encoded has no stored form")
    func unencodableValue() {
        let key = SettingKey<Unencodable>.json("hotkey.combo", default: Unencodable())

        #expect(encoded(key, Unencodable()) == nil)
    }
}
