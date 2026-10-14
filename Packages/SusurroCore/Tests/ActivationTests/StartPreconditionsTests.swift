import Activation
import Domain
import Testing

@Suite("Start preconditions")
struct StartPreconditionsTests {
    @Test("a microphone that is not granted points to the permissions", arguments: [PermissionStatus.denied, .notDetermined])
    func microphone(status: PermissionStatus) {
        let failure = StartPreconditions.evaluate(microphone: status, recognizer: .ready)

        #expect(failure == .microphoneNotGranted)
        #expect(failure?.remedy == .permissions)
    }

    @Test("a recognizer that is not installed points to the settings")
    func notInstalled() {
        let failure = StartPreconditions.evaluate(microphone: .granted, recognizer: .notInstalled)

        #expect(failure == .recognizerNotInstalled)
        #expect(failure?.remedy == .settings)
    }

    @Test("a cloud recognizer without a key asks for one")
    func cloudWithoutKey() {
        let failure = StartPreconditions.evaluate(microphone: .granted, recognizer: .ready, key: .missing)

        #expect(failure == .cloudKeyMissing)
        #expect(failure?.remedy == .addKey)
    }

    @Test("a recognizer that is loading is allowed, and so is one that is ready or has its key")
    func allowed() {
        #expect(StartPreconditions.evaluate(microphone: .granted, recognizer: .loading(progress: 0.3)) == nil)
        #expect(StartPreconditions.evaluate(microphone: .granted, recognizer: .ready) == nil)
        #expect(StartPreconditions.evaluate(microphone: .granted, recognizer: .ready, key: .present) == nil)
    }

    @Test("a load that failed carries its reason and whether trying again can help", arguments: [true, false])
    func unavailable(retryable: Bool) {
        let failure = StartPreconditions.evaluate(
            microphone: .granted, recognizer: .unavailable("no compute", retryable: retryable))

        #expect(failure == .recognizerUnavailable("no compute", retryable: retryable))
        #expect(failure?.remedy == (retryable ? .retry : .settings))
    }

    @Test("the microphone is checked before the recognizer, and the recognizer before the key")
    func order() {
        #expect(
            StartPreconditions.evaluate(microphone: .denied, recognizer: .notInstalled, key: .missing)
                == .microphoneNotGranted)
        #expect(
            StartPreconditions.evaluate(microphone: .granted, recognizer: .notInstalled, key: .missing)
                == .recognizerNotInstalled)
    }
}
