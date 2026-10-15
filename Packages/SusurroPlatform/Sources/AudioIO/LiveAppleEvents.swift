import AppKit
import CoreServices

/// Sends Apple Events to running apps, addressed by process identifier so that no event ever launches an app.
///
/// Before the first event to an app it asks for the Automation permission, which shows the system prompt once per app
/// (the app's `NSAppleEventsUsageDescription` explains it); a hardened runtime also needs the
/// `com.apple.security.automation.apple-events` entitlement. Both calls block, the prompt until the user answers, so
/// they run on a queue of their own, never on the main thread or the cooperative pool. It needs a real app and a person
/// to answer the prompt, so it is covered by the manual check; `ScriptedMediaPlayer`, which uses it, is tested.
public struct LiveAppleEvents: AppleEventSending {
    /// How long an app has to answer one event.
    private static let timeout: TimeInterval = 2
    private static let queue = DispatchQueue(label: "dev.claudiojara.susurro.apple-events", qos: .userInitiated)

    public init() {}

    public func processIdentifier(of bundleIdentifier: String) -> Int32? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .first { !$0.isTerminated }?.processIdentifier
    }

    public func send(_ request: AppleEventRequest, to process: Int32) async throws(AppleEventFailure) -> FourCharCode? {
        let result: Reply = await withCheckedContinuation { continuation in
            Self.queue.async { continuation.resume(returning: Self.sendNow(request, to: process)) }
        }
        return try result.get()
    }

    private typealias Reply = Result<FourCharCode?, AppleEventFailure>

    private static func sendNow(_ request: AppleEventRequest, to process: Int32) -> Reply {
        let target = NSAppleEventDescriptor(processIdentifier: process)
        let event = appleEvent(request, to: target)
        // Asked for the very event that follows, so the prompt (shown once per app) and the answer match it.
        let permission = AEDeterminePermissionToAutomateTarget(target.aeDesc, event.eventClass, event.eventID, true)
        guard permission == noErr else { return .failure(AppleEventFailure(code: Int(permission))) }
        do {
            let reply = try event.sendEvent(options: [.waitForReply], timeout: timeout)
            return .success(reply.paramDescriptor(forKeyword: keyDirectObject)?.enumCodeValue)
        } catch {
            return .failure(AppleEventFailure(code: (error as NSError).code))
        }
    }

    private static func appleEvent(_ request: AppleEventRequest, to target: NSAppleEventDescriptor)
        -> NSAppleEventDescriptor
    {
        switch request {
        case .getProperty(let property):
            let event = NSAppleEventDescriptor.appleEvent(
                withEventClass: AEEventClass(kAECoreSuite), eventID: AEEventID(kAEGetData),
                targetDescriptor: target, returnID: AEReturnID(kAutoGenerateReturnID),
                transactionID: AETransactionID(kAnyTransactionID))
            event.setParam(propertySpecifier(property), forKeyword: keyDirectObject)
            return event
        case .command(let suite, let id):
            return NSAppleEventDescriptor.appleEvent(
                withEventClass: suite, eventID: id, targetDescriptor: target,
                returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        }
    }

    /// The object specifier of a property of the application: `property <code> of application`.
    private static func propertySpecifier(_ property: FourCharCode) -> NSAppleEventDescriptor {
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(
            NSAppleEventDescriptor(typeCode: DescType(cProperty)), forKeyword: AEKeyword(keyAEDesiredClass))
        record.setDescriptor(
            NSAppleEventDescriptor(enumCode: DescType(formPropertyID)), forKeyword: AEKeyword(keyAEKeyForm))
        record.setDescriptor(NSAppleEventDescriptor(typeCode: property), forKeyword: AEKeyword(keyAEKeyData))
        record.setDescriptor(NSAppleEventDescriptor.null(), forKeyword: AEKeyword(keyAEContainer))
        return record.coerce(toDescriptorType: DescType(typeObjectSpecifier)) ?? record
    }
}
