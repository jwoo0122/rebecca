import AppKit
import ApplicationServices
import Foundation
import ScreenCaptureKit


/// Resolves a ScreenCaptureKit window ID to its owning process ID.
func findWindowOwnerPID(windowID: UInt32, deadline: UInt64 = UInt64.max) throws -> pid_t {
    let snapshot = try queryWindowSnapshot(deadline: deadline)
    guard let observation = snapshot.observations.first(where: { $0.info.windowID == windowID }) else {
        throw ActionError.failed("Window \(windowID) not found.")
    }
    guard let ownerPID = observation.info.ownerPID, ownerPID > 0 else {
        throw ActionError.failed("Window \(windowID) has no owner PID.")
    }
    return pid_t(ownerPID)
}

/// Finds an AXUIElement window matching the given SCWindowID.
func findAXWindow(windowID: UInt32, deadline: UInt64 = UInt64.max) throws -> AXUIElement {
    let snapshot = try queryWindowSnapshot(deadline: deadline)
    guard let observation = snapshot.observations.first(where: { $0.info.windowID == windowID }) else {
        throw ActionError.failed("Window \(windowID) not found.")
    }

    guard let pid = observation.info.ownerPID else {
        throw ActionError.failed("Window \(windowID) has no owner PID.")
    }

    let appElement = AXUIElementCreateApplication(pid_t(pid))
    var windowsRef: CFTypeRef?
    let axError = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
    guard axError == .success, let windows = windowsRef as? [AXUIElement] else {
        throw ActionError.failed("Could not retrieve windows for PID \(pid).")
    }

    // Match by frame position and size
    let targetFrame = observation.info.logicalFrame
    for window in windows {
        if let frame = try? axFrameFromElement(window) {
            if abs(frame.x - targetFrame.x) < 1.0
                && abs(frame.y - targetFrame.y) < 1.0
                && abs(frame.width - targetFrame.width) < 1.0
                && abs(frame.height - targetFrame.height) < 1.0
            {
                return window
            }
        }
    }

    throw ActionError.failed("Window \(windowID) could not be matched to an AX element.")
}

/// Moves a window to the given global logical coordinates.
func axWindowMove(windowID: UInt32, x: Double, y: Double, deadline: UInt64) throws {
    guard AXIsProcessTrusted() else {
        throw ActionError.permissionDenied
    }
    let window = try findAXWindow(windowID: windowID, deadline: deadline)
    var position = CGPoint(x: CGFloat(x), y: CGFloat(y))
    guard AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &position)!) == .success else {
        throw ActionError.failed("Failed to set window position.")
    }
}

/// Resizes a window to the given dimensions.
func axWindowResize(windowID: UInt32, width: Double, height: Double, deadline: UInt64) throws {
    guard AXIsProcessTrusted() else {
        throw ActionError.permissionDenied
    }
    let window = try findAXWindow(windowID: windowID, deadline: deadline)
    var size = CGSize(width: CGFloat(width), height: CGFloat(height))
    guard AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &size)!) == .success else {
        throw ActionError.failed("Failed to set window size.")
    }
}

/// Closes a window via AX press on the close button, or AXClose action.
func axWindowClose(windowID: UInt32, deadline: UInt64) throws {
    guard AXIsProcessTrusted() else {
        throw ActionError.permissionDenied
    }
    let window = try findAXWindow(windowID: windowID, deadline: deadline)

    // Try the AXClose action first
    var actionNames: CFArray?
    if AXUIElementCopyActionNames(window, &actionNames) == .success,
       let names = actionNames as? [String],
       names.contains("AXClose") {
        if AXUIElementPerformAction(window, "AXClose" as CFString) == .success {
            return
        }
    }

    // Fall back to finding and pressing the close button
    var closeRef: CFTypeRef?
    if AXUIElementCopyAttributeValue(window, kAXCloseButtonAttribute as CFString, &closeRef) == .success,
       let closeButton = closeRef {
        let button = closeButton as! AXUIElement
        if AXUIElementPerformAction(button, kAXPressAction as CFString) == .success {
            return
        }
    }

    throw ActionError.failed("Failed to close window \(windowID).")
}
