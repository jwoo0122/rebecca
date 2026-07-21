import AppKit
import ApplicationServices
import Foundation

enum ActionError: Error {
    case permissionDenied
    case staleObservation(provided: UInt64, current: UInt64)
    case elementNotFound
    case actionNotSupported(String)
    case secureFieldBlocked
    case failed(String)
}

struct ActionResult {
    let executed: Bool
    let method: String
    let beforeRevision: UInt64
    let afterRevision: UInt64
}

/// Press an AX element using `AXPress` action.
/// Does not activate the window — tries background AX first.
func axPressElement(
    _ element: AXUIElement,
    elementID: String,
    providedRevision: UInt64,
    cache: ElementCache,
    observationTracker: ObservationRevisionTracker,
    deadline: UInt64
) throws -> ActionResult {
    guard AXIsProcessTrusted() else {
        throw ActionError.permissionDenied
    }

    // Stale check
    let currentRevision = cache.currentRevision
    if providedRevision != currentRevision {
        throw ActionError.staleObservation(provided: providedRevision, current: currentRevision)
    }

    // Verify the element still resolves
    guard cache.resolve(elementID, revision: providedRevision) != nil else {
        throw ActionError.elementNotFound
    }

    let beforeRevision = cache.currentRevision

    // Check if element supports AXPress
    var actionNames: CFArray?
    let actionError = AXUIElementCopyActionNames(element, &actionNames)
    guard actionError == .success,
          let names = actionNames as? [String],
          names.contains("AXPress") else {
        throw ActionError.actionNotSupported("AXPress")
    }

    // Try AXPress without window activation
    var pressError = AXUIElementPerformAction(element, kAXPressAction as CFString)
    let method: String

    if pressError != .success {
        // Fallback: activate the window and retry
        method = "ax_press_after_activate"
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        if pid > 0 {
            let app = NSRunningApplication(processIdentifier: pid)
            app?.activate(options: .activateAllWindows)
        }
        pressError = AXUIElementPerformAction(element, kAXPressAction as CFString)
    } else {
        method = "ax_press_background"
    }

    guard pressError == .success else {
        throw ActionError.failed("AXPress failed with error \(pressError.rawValue)")
    }

    // Bump revision since an action was performed
    let afterRevision = try observationTracker.revision(
        for: .windows,
        fingerprint: observationFingerprint(ActionFingerprint(action: "press", elementID: elementID))
    )
    cache.beginRevision(afterRevision)

    return ActionResult(executed: true, method: method, beforeRevision: beforeRevision, afterRevision: afterRevision)
}

/// Set the value of an AX text field using `AXSetValue`.
/// Refuses secure text fields.
func axSetValue(
    _ element: AXUIElement,
    elementID: String,
    providedRevision: UInt64,
    value: String,
    cache: ElementCache,
    observationTracker: ObservationRevisionTracker,
    deadline: UInt64
) throws -> ActionResult {
    guard AXIsProcessTrusted() else {
        throw ActionError.permissionDenied
    }

    let currentRevision = cache.currentRevision
    if providedRevision != currentRevision {
        throw ActionError.staleObservation(provided: providedRevision, current: currentRevision)
    }

    guard cache.resolve(elementID, revision: providedRevision) != nil else {
        throw ActionError.elementNotFound
    }

    let beforeRevision = cache.currentRevision

    // Check for secure field
    let isSecure = (axBool(element, "AXIsSecure") ?? false)
        || (axString(element, kAXSubroleAttribute)?.contains("Secure") ?? false)
        || (axString(element, kAXRoleAttribute)?.contains("Secure") ?? false)
    if isSecure {
        throw ActionError.secureFieldBlocked
    }

    // Check if element supports setting value
    var settable: DarwinBoolean = false
    let isSettableError = AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable)
    guard isSettableError == .success, settable.boolValue else {
        throw ActionError.actionNotSupported("AXSetValue")
    }

    // Try setting value without window activation
    let nsValue = value as NSString
    var setValueError = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, nsValue)
    let method: String

    if setValueError != .success {
        // Fallback: activate and retry
        method = "ax_set_value_after_activate"
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        if pid > 0 {
            let app = NSRunningApplication(processIdentifier: pid)
            app?.activate(options: .activateAllWindows)
        }
        setValueError = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, nsValue)
    } else {
        method = "ax_set_value_background"
    }

    guard setValueError == .success else {
        throw ActionError.failed("AXSetValue failed with error \(setValueError.rawValue)")
    }

    let afterRevision = try observationTracker.revision(
        for: .windows,
        fingerprint: observationFingerprint(ActionFingerprint(action: "set_value", elementID: elementID))
    )
    cache.beginRevision(afterRevision)

    return ActionResult(executed: true, method: method, beforeRevision: beforeRevision, afterRevision: afterRevision)
}

struct ActionFingerprint: Encodable {
    let action: String
    let elementID: String
}

func actionError(_ error: ActionError) -> (code: String, message: String, details: [String: Any]?) {
    switch error {
    case .permissionDenied:
        return ("permission_denied", "Accessibility permission is required.", nil)
    case let .staleObservation(provided, current):
        return ("stale_observation", "Element belongs to an old revision.", ["provided_revision": provided, "current_revision": current])
    case .elementNotFound:
        return ("target_not_found", "Element was not found in the current revision.", nil)
    case let .actionNotSupported(action):
        return ("unsupported", "Element does not support \(action).", nil)
    case .secureFieldBlocked:
        return ("security_rejection", "Cannot set value on a secure text field.", nil)
    case let .failed(message):
        return ("internal_error", message, nil)
    }
}

// MARK: - App activation

func axActivateApp(bundleID: String) throws {
    let apps = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == bundleID }
    if let app = apps.first {
        app.unhide()
        app.activate()
        return
    }
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
        throw ActionError.failed("Application with bundle ID '\(bundleID)' not found.")
    }
    let config = NSWorkspace.OpenConfiguration()
    NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in }
}
