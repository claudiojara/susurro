import Foundation
import Testing

@testable import Domain

@Suite("Setting key", .timeLimit(.minutes(1)))
struct SettingKeyTests {
    private enum Edge: String, Sendable {
        case top
        case bottom
    }

    private struct Combo: Codable, Sendable, Equatable {
        var keyCode: Int
        var modifiers: [String]
    }

    @Test("a key is stored under its name and carries its default")
    func nameAndDefault() {
        let key = SettingKey<Int>("history.retentionDays", default: 7)

        #expect(key.storageName == "history.retentionDays")
        #expect(key.defaultValue == 7)
    }

    @Test("a basic value is stored as itself and read back as the same value")
    func basicValuesRoundTrip() {
        let flag = SettingKey<Bool>("general.launchAtLogin", default: false)
        let count = SettingKey<Int>("history.retentionDays", default: 7)
        let seconds = SettingKey<Double>("hotkey.holdThreshold", default: 0.3)
        let text = SettingKey<String>("speech.language", default: "auto")

        #expect(flag.encode(true) as? Bool == true)
        #expect(flag.decode(flag.encode(true)) == true)
        #expect(count.encode(30) as? Int == 30)
        #expect(count.decode(count.encode(30)) == 30)
        #expect(seconds.encode(0.45) as? Double == 0.45)
        #expect(seconds.decode(seconds.encode(0.45)) == 0.45)
        #expect(text.encode("es") as? String == "es")
        #expect(text.decode(text.encode("es")) == "es")
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
    func rawRepresentableValues() {
        let key = SettingKey<Edge>("overlay.edge", default: .bottom)

        #expect(key.encode(.top) as? String == "top")
        #expect(key.decode("top") == .top)
        #expect(key.decode("bottom") == .bottom)
        #expect(key.decode("diagonal") == nil)
        #expect(key.decode(3) == nil)
    }

    @Test("a Codable value is stored as JSON data, and data that is not that value is not read")
    func jsonValues() throws {
        let key = SettingKey<Combo>.json("hotkey.combo", default: Combo(keyCode: 2, modifiers: ["control"]))
        let combo = Combo(keyCode: 40, modifiers: ["control", "option"])

        let stored = try #require(key.encode(combo) as? Data)

        #expect(key.decode(stored) == combo)
        #expect(key.decode(Data("not json".utf8)) == nil)
        #expect(key.decode(Data(#"{"keyCode":"forty"}"#.utf8)) == nil)
        #expect(key.decode("{\"keyCode\":40,\"modifiers\":[]}") == nil)
    }
}
