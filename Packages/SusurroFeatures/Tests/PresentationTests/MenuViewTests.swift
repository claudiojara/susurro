import Domain
import Testing

@testable import Presentation

@Suite("Menu view", .timeLimit(.minutes(1)))
struct MenuViewTests {
    @Test(
        "an item sends its step to the handler of that kind, for its own permission",
        arguments: [Permission.microphone, .accessibility]
    )
    func itemDispatchesByKind(permission: Permission) {
        var requested: [Permission] = []
        var opened: [Permission] = []
        let allow = MenuContent.PermissionRow.Action(kind: .request, title: "Allow")
        let settings = MenuContent.PermissionRow.Action(kind: .openSettings, title: "Open")

        MenuView.perform(
            allow, for: permission, onRequest: { requested.append($0) }, onOpenSettings: { opened.append($0) })
        let afterAllow = (requested, opened)
        MenuView.perform(
            settings, for: permission, onRequest: { requested.append($0) }, onOpenSettings: { opened.append($0) })

        #expect(afterAllow.0 == [permission])
        #expect(afterAllow.1.isEmpty)
        #expect(requested == [permission])
        #expect(opened == [permission])
    }
}
