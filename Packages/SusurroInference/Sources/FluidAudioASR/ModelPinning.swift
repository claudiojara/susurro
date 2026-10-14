import FluidAudio
import Synchronization

/// Points FluidAudio at Hugging Face and at the reviewed commit of each model repository. FluidAudio reads both settings
/// from process-wide state, and two models load at once (the speech model at launch and the voice activity model on the
/// first dictation), so the changes go through one lock.
enum ModelPinning {
    private static let lock = Mutex(())

    /// Sets the host, which also overrides the registry variables of the environment that could send the download
    /// somewhere else, and pins `repository` to `revision`. Calling it again with the same values changes nothing.
    static func pin(repository: String, to revision: String) {
        lock.withLock { _ in
            ModelRegistry.baseURL = "https://huggingface.co"
            ModelRegistry.revisionOverrides[repository] = revision
        }
    }
}
