import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import ScreenCaptureKit

struct FocusedApp: Encodable, Equatable {
    let pid: UInt32
    let bundleID: String?
    let name: String?

    enum CodingKeys: String, CodingKey {
        case pid
        case bundleID = "bundle_id"
        case name
    }
}

struct FocusedWindow: Encodable, Equatable {
    let windowID: UInt32?
    let title: String?
    let logicalFrame: LogicalFrame?

    enum CodingKeys: String, CodingKey {
        case windowID = "window_id"
        case title
        case logicalFrame = "logical_frame"
    }
}

struct FocusedElement: Encodable, Equatable {
    let role: String
    let label: String?
    let description: String?
    let logicalFrame: LogicalFrame?

    enum CodingKeys: String, CodingKey {
        case role
        case label
        case description
        case logicalFrame = "logical_frame"
    }
}

struct FocusFingerprint: Encodable {
    let pid: UInt32
    let bundleID: String?
    let name: String?
}

enum FocusQueryError: Error {
    case permissionDenied
    case failed(String)
}

func queryFocusedState(deadline: UInt64 = UInt64.max) throws -> (FocusedApp, FocusedWindow?, FocusedElement?) {
    guard AXIsProcessTrusted() else {
        throw FocusQueryError.permissionDenied
    }

    let systemWide = AXUIElementCreateSystemWide()

    var focusedAppRaw: CFTypeRef?
    let appError = AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &focusedAppRaw)
    guard appError == .success, let focusedAppRef = focusedAppRaw else {
        throw FocusQueryError.failed("Unable to determine the focused application.")
    }
    let focusedAppElement = focusedAppRef as! AXUIElement

    let focusedApp = try buildFocusedApp(from: focusedAppElement)
    let focusedWindow = try? buildFocusedWindow(from: focusedAppElement, deadline: deadline)
    let focusedElement = try? buildFocusedElement(from: focusedAppElement)

    return (focusedApp, focusedWindow, focusedElement)
}

private func buildFocusedApp(from appRef: AXUIElement) throws -> FocusedApp {
    var pid: pid_t = 0
    let pidError = AXUIElementGetPid(appRef, &pid)
    guard pidError == .success else {
        throw FocusQueryError.failed("Unable to get focused app PID.")
    }

    let bundleID = axString(appRef, "AXBundleIdentifier")
    let name = axString(appRef, kAXTitleAttribute)
    return FocusedApp(pid: UInt32(pid), bundleID: bundleID, name: name)
}

private func buildFocusedWindow(from appRef: AXUIElement, deadline: UInt64) throws -> FocusedWindow {
    var windowRaw: CFTypeRef?
    let windowError = AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &windowRaw)
    guard windowError == .success, let windowRef = windowRaw else {
        return FocusedWindow(windowID: nil, title: nil, logicalFrame: nil)
    }
    let windowElement = windowRef as! AXUIElement

    let title = axString(windowElement, kAXTitleAttribute)
    let frame = try? axFrame(windowElement)
    let windowID = try? correlateWindowID(from: appRef, title: title, frame: frame, deadline: deadline)

    return FocusedWindow(windowID: windowID, title: title, logicalFrame: frame)
}

private func buildFocusedElement(from appRef: AXUIElement) throws -> FocusedElement? {
    var elementRaw: CFTypeRef?
    let elementError = AXUIElementCopyAttributeValue(appRef, kAXFocusedUIElementAttribute as CFString, &elementRaw)
    guard elementError == .success, let elementRef = elementRaw else {
        return nil
    }
    let elementElement = elementRef as! AXUIElement

    let role = axString(elementElement, kAXRoleAttribute) ?? "unknown"
    let label = axString(elementElement, kAXDescriptionAttribute)
    let description = axString(elementElement, kAXHelpAttribute)
    let frame = try? axFrame(elementElement)
    return FocusedElement(role: role, label: label, description: description, logicalFrame: frame)
}

private func axFrame(_ element: AXUIElement) throws -> LogicalFrame {
    var positionRaw: CFTypeRef?
    let posError = AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRaw)
    guard posError == .success, let positionValue = positionRaw else {
        throw FocusQueryError.failed("Unable to get AX position.")
    }
    let positionAXValue = positionValue as! AXValue
    var point = CGPoint.zero
    guard AXValueGetValue(positionAXValue, .cgPoint, &point) else {
        throw FocusQueryError.failed("Unable to extract AX position.")
    }

    var sizeRaw: CFTypeRef?
    let sizeError = AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRaw)
    guard sizeError == .success, let sizeValue = sizeRaw else {
        throw FocusQueryError.failed("Unable to get AX size.")
    }
    let sizeAXValue = sizeValue as! AXValue
    var size = CGSize.zero
    guard AXValueGetValue(sizeAXValue, .cgSize, &size) else {
        throw FocusQueryError.failed("Unable to extract AX size.")
    }

    return LogicalFrame(x: Double(point.x), y: Double(point.y), width: Double(size.width), height: Double(size.height))
}

private func correlateWindowID(from appRef: AXUIElement, title: String?, frame: LogicalFrame?, deadline: UInt64) throws -> UInt32? {
    guard CGPreflightScreenCaptureAccess() else { return nil }
    let content: SCShareableContent
    do {
        content = try queryShareableContent(deadline: deadline)
    } catch {
        return nil
    }

    var pid: pid_t = 0
    guard AXUIElementGetPid(appRef, &pid) == .success else { return nil }
    let candidates = content.windows.filter { window in
        guard let owner = window.owningApplication, owner.processID == pid else { return false }
        if let title, let windowTitle = window.title, windowTitle != title { return false }
        if let frame {
            let wf = window.frame
            return abs(wf.origin.x - CGFloat(frame.x)) <= 2
                && abs(wf.origin.y - CGFloat(frame.y)) <= 2
                && abs(wf.width - CGFloat(frame.width)) <= 2
                && abs(wf.height - CGFloat(frame.height)) <= 2
        }
        return true
    }
    return candidates.first.flatMap { UInt32(exactly: $0.windowID) }
}
