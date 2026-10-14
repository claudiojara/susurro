import CoreTestSupport
import Domain
import Testing

@Suite("Setting key catalog check", .timeLimit(.minutes(1)))
struct SettingKeyCatalogTests {
    private static let days = SettingKey<Int>(area: "history", name: "retentionDays", default: 7)
    private static let launch = SettingKey<Bool>(area: "general", name: "launchAtLogin", default: true)
    private static let language = SettingKey<String>(area: "speech", name: "language", default: "auto")

    @Test("a catalog whose keys are stored under different names passes, whatever their value types")
    func uniqueNamesPass() throws {
        try requireUniqueStorageNames([Self.days, Self.launch, Self.language])
        try requireUniqueStorageNames([])
    }

    @Test("two keys stored under one name fail, and the name is given once, in the order it first repeats")
    func duplicatesAreNamed() {
        let daysAsText = SettingKey<String>(area: "history", name: "retentionDays", default: "week")
        let launchAgain = SettingKey<Bool>(area: "general", name: "launchAtLogin", default: false)
        let keys: [any AnySettingKey] = [Self.days, Self.launch, daysAsText, Self.language, launchAgain, daysAsText]

        #expect(throws: DuplicateSettingKeys(names: ["history.retentionDays", "general.launchAtLogin"])) {
            try requireUniqueStorageNames(keys)
        }
    }

    @Test("the failure says which names collide")
    func failureDescription() {
        let error = DuplicateSettingKeys(names: ["history.retentionDays", "general.launchAtLogin"])

        #expect(
            error.description
                == "Setting keys share a storage name: history.retentionDays, general.launchAtLogin")
    }
}
