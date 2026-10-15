import CoreTestSupport
import Domain
import SusurroUI
import Synchronization
import Testing

@testable import Presentation
@testable import SusurroUI

/// The keys of a recording, scripted by the test. It counts how many recordings were started and how many still listen.
private final class FakeCaptureSource: HotkeyCaptureSource {
    private struct State {
        var continuation: AsyncStream<HotkeyCaptureInput>.Continuation?
        var started = 0
        var listening = 0
    }

    private let state = Mutex(State())

    func inputs() -> AsyncStream<HotkeyCaptureInput> {
        let (stream, continuation) = AsyncStream.makeStream(of: HotkeyCaptureInput.self)
        state.withLock {
            $0.continuation = continuation
            $0.started += 1
            $0.listening += 1
        }
        continuation.onTermination = { _ in self.state.withLock { $0.listening -= 1 } }
        return stream
    }

    var started: Int { state.withLock { $0.started } }
    var isListening: Bool { state.withLock { $0.listening > 0 } }
    func send(_ input: HotkeyCaptureInput) { _ = state.withLock { $0.continuation }?.yield(input) }
    func finish() { state.withLock { $0.continuation }?.finish() }
}

/// An in-memory store that remembers which keys were removed, since a removal and a store of the default read the same.
private final class RemovalSpy: SettingsStore {
    private let base = InMemorySettingsStore()
    private let removals = Mutex<[String]>([])

    var removed: [String] { removals.withLock { $0 } }

    func value<Value>(for key: SettingKey<Value>) -> Value { base.value(for: key) }
    func set<Value>(_ value: Value, for key: SettingKey<Value>) { base.set(value, for: key) }
    func remove<Value>(_ key: SettingKey<Value>) {
        removals.withLock { $0.append(key.storageName) }
        base.remove(key)
    }
    func changes() -> AsyncStream<SettingChange> { base.changes() }
}

@MainActor
private struct RecorderRig {
    let settings = RemovalSpy()
    let source = FakeCaptureSource()
    var takenBySystem = false

    func model() -> HotkeyRecorderViewModel {
        let taken = takenBySystem
        return HotkeyRecorderViewModel(settings: settings, source: source, isTakenBySystem: { _ in taken })
    }
}

@MainActor
@Suite("Hotkey recorder view model", .timeLimit(.minutes(1)))
struct HotkeyRecorderViewModelTests {
    private static let a = 0
    private static let escape = 53
    private static let controlShift: HotkeyModifiers = [.control, .shift]

    private func keyed(_ code: Int, _ modifiers: HotkeyModifiers) -> HotkeyConfiguration {
        HotkeyConfiguration(kind: .keyed, combo: HotkeyCombo(keyCode: code, modifiers: modifiers))
    }

    /// Waits for what the model does on its own task after a key was sent.
    private func until(_ condition: @MainActor () -> Bool) async {
        while !condition() { await Task.yield() }
    }

    // MARK: Resting

    @Test("with no hotkey chosen the recorder rests, and there is nothing to restore")
    func resting() {
        let state = RecorderRig().model().state

        #expect(state == HotkeyRecorderState(phase: .idle, rejection: nil, canRestoreDefault: false))
    }

    @Test("a hotkey that is not the default can be restored")
    func restorable() {
        let rig = RecorderRig()
        rig.settings.setHotkey(keyed(Self.a, Self.controlShift))

        #expect(rig.model().state.canRestoreDefault)
    }

    // MARK: Listening

    @Test("begin listens, and begin again while listening starts nothing new")
    func begin() async {
        let rig = RecorderRig()
        let model = rig.model()

        model.begin()
        model.begin()
        await until { rig.source.started == 1 && rig.source.isListening }

        #expect(model.state.phase == .listening(held: []))
        #expect(rig.source.started == 1)
    }

    @Test("the modifier keys that are held show as key caps while the recorder listens")
    func heldKeys() async {
        let rig = RecorderRig()
        let model = rig.model()
        model.begin()

        rig.source.send(.modifiers([.control, .option]))
        await until { model.state.phase != .listening(held: []) }

        #expect(model.state.phase == .listening(held: ["⌃", "⌥"]))
    }

    // MARK: Choosing

    @Test("a keyed shortcut that is allowed is stored as the hotkey, and the recorder rests")
    func keyedShortcut() async {
        let rig = RecorderRig()
        let model = rig.model()
        model.begin()

        rig.source.send(.key(code: Self.a, modifiers: Self.controlShift))
        await until { model.state.phase == .idle }

        #expect(rig.settings.hotkeyConfiguration() == keyed(Self.a, Self.controlShift))
        #expect(model.state == HotkeyRecorderState(phase: .idle, rejection: nil, canRestoreDefault: true))
        await until { !rig.source.isListening }  // the keys go back to the app
    }

    @Test("fn alone is stored as a modifier-only hotkey once it is let go")
    func functionKey() async {
        let rig = RecorderRig()
        let model = rig.model()
        model.begin()

        rig.source.send(.modifiers(.function))
        rig.source.send(.modifiers([]))
        await until { model.state.phase == .idle }

        let fn = HotkeyConfiguration(kind: .modifierOnly, combo: HotkeyCombo(keyCode: nil, modifiers: .function))
        #expect(rig.settings.hotkeyConfiguration() == fn)
    }

    @Test("a shortcut that is refused says why, changes nothing, and the recorder goes on listening")
    func refusedShortcut() async {
        let rig = RecorderRig()
        let model = rig.model()
        model.begin()

        rig.source.send(.key(code: Self.a, modifiers: .shift))
        await until { model.state.rejection != nil }

        #expect(model.state.rejection == SettingsCopy.rejection(.needsStrongerModifiers))
        #expect(model.state.phase == .listening(held: ["⇧"]))  // Shift is still down
        #expect(rig.settings.hotkeyConfiguration() == .standard)
        #expect(rig.source.isListening)
    }

    @Test("a shortcut that is allowed after a refused one is stored, and the reason goes away")
    func allowedAfterRefused() async {
        let rig = RecorderRig()
        let model = rig.model()
        model.begin()
        rig.source.send(.key(code: Self.a, modifiers: .shift))
        await until { model.state.rejection != nil }

        rig.source.send(.key(code: Self.a, modifiers: .control))
        await until { model.state.phase == .idle }

        #expect(model.state.rejection == nil)
        #expect(rig.settings.hotkeyConfiguration() == keyed(Self.a, .control))
    }

    @Test("a single modifier key is refused as a modifier-only hotkey")
    func singleModifier() async {
        let rig = RecorderRig()
        let model = rig.model()
        model.begin()

        rig.source.send(.modifiers(.command))
        rig.source.send(.modifiers([]))
        await until { model.state.rejection != nil }

        #expect(model.state.rejection == SettingsCopy.rejection(.needsFunctionOrTwoModifiers))
        #expect(rig.settings.hotkeyConfiguration() == .standard)
    }

    @Test("a shortcut that System Settings already uses is refused")
    func takenBySystem() async {
        var rig = RecorderRig()
        rig.takenBySystem = true
        let model = rig.model()
        model.begin()

        rig.source.send(.key(code: Self.a, modifiers: .control))
        await until { model.state.rejection != nil }

        #expect(model.state.rejection == SettingsCopy.rejection(.takenBySystem))
        #expect(rig.settings.hotkeyConfiguration() == .standard)
    }

    // MARK: Giving up

    @Test("Escape gives up: the hotkey stays and the recorder rests")
    func escape() async {
        let rig = RecorderRig()
        let model = rig.model()
        model.begin()

        rig.source.send(.key(code: Self.escape, modifiers: []))
        await until { model.state.phase == .idle }

        #expect(rig.settings.hotkeyConfiguration() == .standard)
        await until { !rig.source.isListening }
    }

    @Test("cancel stops listening and forgets the reason of a refused shortcut")
    func cancel() async {
        let rig = RecorderRig()
        let model = rig.model()
        model.begin()
        rig.source.send(.key(code: Self.a, modifiers: .shift))
        await until { model.state.rejection != nil }

        model.cancel()

        #expect(model.state == HotkeyRecorderState(phase: .idle, rejection: nil, canRestoreDefault: false))
        await until { !rig.source.isListening }
    }

    @Test("a recording that the source ends, because the window lost the keys, rests")
    func sourceEnds() async {
        let rig = RecorderRig()
        let model = rig.model()
        model.begin()
        await until { rig.source.isListening }

        rig.source.finish()
        await until { model.state.phase == .idle }

        #expect(rig.settings.hotkeyConfiguration() == .standard)
    }

    @Test("a new recording is not ended by the end of the one before it")
    func newRecordingSurvives() async {
        let rig = RecorderRig()
        let model = rig.model()
        model.begin()
        await until { rig.source.started == 1 }
        model.cancel()

        model.begin()
        await until { rig.source.started == 2 }
        for _ in 0..<50 { await Task.yield() }  // the first recording has had time to end

        #expect(model.state.phase == .listening(held: []))
    }

    // MARK: Restoring

    @Test("restoring the default brings the default hotkey back and stores nothing, so the default can still change")
    func restoreDefault() {
        let rig = RecorderRig()
        rig.settings.setHotkey(keyed(Self.a, Self.controlShift))
        let model = rig.model()

        model.restoreDefault()

        #expect(rig.settings.hotkeyConfiguration() == .standard)
        #expect(Set(rig.settings.removed) == ["hotkey.kind", "hotkey.combo"])
        #expect(model.state.canRestoreDefault == false)
    }

    // MARK: Words

    @Test("the refusal of the fixture is the one the view model gives, down to the last word")
    func fixtureWords() {
        #expect(SettingsFixtures.recorderRefused.rejection == SettingsCopy.rejection(.needsStrongerModifiers))
    }

    @Test("every reason has a sentence of its own")
    func everyReasonIsTold() {
        let sentences = HotkeyRejection.allCases.map(SettingsCopy.rejection)

        #expect(Set(sentences).count == HotkeyRejection.allCases.count)
        #expect(sentences.allSatisfy { !$0.isEmpty })
    }
}

@MainActor
@Suite("Hotkey recorder view model: paste last dictation", .timeLimit(.minutes(1)))
struct PasteLastRecorderTests {
    private let settings = RemovalSpy()
    private let source = FakeCaptureSource()

    private func model() -> HotkeyRecorderViewModel {
        HotkeyRecorderViewModel(binding: .pasteLast(settings), source: source, isTakenBySystem: { _ in false })
    }

    private func until(_ condition: @MainActor () -> Bool) async {
        while !condition() { await Task.yield() }
    }

    @Test("unassigned, there is nothing to remove; the button that removes it is named so")
    func resting() {
        let state = model().state
        #expect(state.canRestoreDefault == false)
        #expect(state.restoreTitle == "Remove shortcut")
    }

    @Test("an allowed shortcut is stored as the paste last dictation shortcut, not as the dictation hotkey")
    func stores() async {
        let model = model()
        model.begin()
        await until { source.isListening }

        source.send(.key(code: 9, modifiers: [.control, .option]))
        await until { model.state.phase == .idle }

        #expect(
            settings.value(for: PasteLastSettings.combo) == HotkeyCombo(keyCode: 9, modifiers: [.control, .option]))
        #expect(settings.hotkeyConfiguration() == .standard)
        #expect(model.state.canRestoreDefault)
    }

    @Test("the dictation hotkey is refused with the reason, and the recorder goes on listening")
    func refusesDictationHotkey() async {
        let model = model()
        model.begin()
        await until { source.isListening }

        source.send(.key(code: 2, modifiers: [.control, .option]))
        await until { model.state.rejection != nil }

        #expect(model.state.rejection == SettingsCopy.rejection(.sameAsDictation))
        #expect(model.state.phase != .idle)
        #expect(settings.value(for: PasteLastSettings.combo) == nil)
    }

    @Test("modifier keys alone are refused")
    func refusesModifierOnly() async {
        let model = model()
        model.begin()
        await until { source.isListening }

        source.send(.modifiers(.function))
        source.send(.modifiers([]))
        await until { model.state.rejection != nil }

        #expect(model.state.rejection == SettingsCopy.rejection(.needsKey))
    }

    @Test("remove takes the shortcut away")
    func removes() {
        settings.set(HotkeyCombo(keyCode: 9, modifiers: [.control, .option]), for: PasteLastSettings.combo)
        let model = model()

        model.restoreDefault()

        #expect(settings.removed == [PasteLastSettings.combo.storageName])
        #expect(model.state.canRestoreDefault == false)
    }
}

@MainActor
@Suite("Hotkey recorder view model for command mode", .timeLimit(.minutes(1)))
struct CommandHotkeyRecorderViewModelTests {
    private static let f5 = 96

    private func until(_ condition: @MainActor () -> Bool) async {
        while !condition() { await Task.yield() }
    }

    private func commandModel(_ rig: RecorderRig) -> HotkeyRecorderViewModel {
        HotkeyRecorderViewModel(binding: .command(rig.settings), source: rig.source, isTakenBySystem: { _ in false })
    }

    @Test("the command recorder stores the command hotkey and leaves the dictation one alone")
    func storesTheCommandHotkey() async {
        let rig = RecorderRig()
        let model = commandModel(rig)
        model.begin()

        rig.source.send(.key(code: Self.f5, modifiers: []))
        await until { model.state.phase == .idle }

        let f5 = HotkeyConfiguration(kind: .keyed, combo: HotkeyCombo(keyCode: Self.f5, modifiers: []))
        #expect(rig.settings.hotkeyConfiguration(for: .command) == f5)
        #expect(rig.settings.hotkeyConfiguration() == .standard)
        #expect(model.state.canRestoreDefault)
    }

    @Test("a hotkey that the other role uses is refused with the reason, and the recorder goes on listening")
    func refusesTheOtherRolesHotkey() async {
        let rig = RecorderRig()
        let model = commandModel(rig)
        model.begin()

        rig.source.send(.key(code: 2, modifiers: [.control, .option]))
        await until { model.state.rejection != nil }

        #expect(model.state.rejection == SettingsCopy.rejection(.alreadyInUse))
        #expect(rig.settings.hotkeyConfiguration(for: .command) == .command)
        #expect(rig.source.isListening)
    }

    @Test("the dictation recorder refuses the command hotkey too")
    func dictationRefusesTheCommandHotkey() async {
        let rig = RecorderRig()
        let model = rig.model()
        model.begin()

        rig.source.send(.key(code: 2, modifiers: [.control, .option, .shift]))
        await until { model.state.rejection != nil }

        #expect(model.state.rejection == SettingsCopy.rejection(.alreadyInUse))
    }

    @Test("restoring the default of the command recorder removes only the command keys")
    func restoresTheCommandDefault() {
        let rig = RecorderRig()

        commandModel(rig).restoreDefault()

        #expect(Set(rig.settings.removed) == ["hotkey.commandKind", "hotkey.commandCombo"])
    }

    @Test("no shortcut of the app can take the keys of another: the paste last shortcut is refused too")
    func refusesThePasteLastShortcut() async {
        let rig = RecorderRig()
        rig.settings.set(HotkeyCombo(keyCode: 9, modifiers: [.control, .option]), for: PasteLastSettings.combo)
        let model = commandModel(rig)
        model.begin()

        rig.source.send(.key(code: 9, modifiers: [.control, .option]))
        await until { model.state.rejection != nil }

        #expect(model.state.rejection == SettingsCopy.rejection(.alreadyInUse))
    }

    @Test("the paste last shortcut cannot take the command hotkey")
    func pasteLastRefusesTheCommandHotkey() async {
        let rig = RecorderRig()
        let model = HotkeyRecorderViewModel(
            binding: .pasteLast(rig.settings), source: rig.source, isTakenBySystem: { _ in false })
        model.begin()

        rig.source.send(.key(code: 2, modifiers: [.control, .option, .shift]))
        await until { model.state.rejection != nil }

        #expect(model.state.rejection == SettingsCopy.rejection(.alreadyInUse))
        #expect(rig.settings.value(for: PasteLastSettings.combo) == nil)
    }
}
