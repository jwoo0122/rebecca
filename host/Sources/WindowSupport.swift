import CoreGraphics
import Foundation
import ScreenCaptureKit

struct WindowInfo: Encodable, Equatable {
    let windowID: UInt32
    let ownerPID: UInt32?
    let bundleID: String?
    let title: String?
    let logicalFrame: LogicalFrame
    let onscreen: Bool
    let minimized: Bool?
    let focused: Bool?
    let displayID: UInt32?

    enum CodingKeys: String, CodingKey {
        case windowID = "window_id"
        case ownerPID = "owner_pid"
        case bundleID = "bundle_id"
        case title
        case logicalFrame = "logical_frame"
        case onscreen
        case minimized
        case focused
        case displayID = "display_id"
    }
}

struct WindowObservation {
    let info: WindowInfo
    let nativeWindow: SCWindow
}

struct WindowSnapshot {
    let observations: [WindowObservation]

    var infos: [WindowInfo] { observations.map(\.info) }
}

enum WindowQueryError: Error {
    case permissionDenied
    case timedOut
    case failed(String)
}

func queryWindowSnapshot(deadline: UInt64 = UInt64.max) throws -> WindowSnapshot {
    let content: SCShareableContent
    do {
        content = try queryShareableContent(deadline: deadline)
    } catch let error as ScreenCaptureQueryError {
        switch error {
        case .permissionDenied:
            throw WindowQueryError.permissionDenied
        case .timedOut:
            throw WindowQueryError.timedOut
        case let .failed(message):
            throw WindowQueryError.failed(message)
        }
    }

    let frames = windowServerFrames()
    let observations = content.windows.compactMap { window in
        try? windowObservation(for: window, serverFrame: frames[window.windowID])
    }
    return WindowSnapshot(observations: observations.sorted { $0.info.windowID < $1.info.windowID })
}

private func windowObservation(
    for window: SCWindow,
    serverFrame: (frame: CGRect, onscreen: Bool)?
) throws -> WindowObservation {
    let windowID = window.windowID
    guard let windowID = UInt32(exactly: windowID), windowID > 0 else {
        throw WindowQueryError.failed("Window identifier exceeds protocol limits.")
    }
    let frame = serverFrame?.frame ?? window.frame
    guard frame.width > 0, frame.height > 0 else {
        throw WindowQueryError.failed("Window \(windowID) returned invalid geometry.")
    }

    let ownerPID = window.owningApplication.flatMap { UInt32(exactly: $0.processID) }
    let onscreen = serverFrame?.onscreen ?? window.isOnScreen
    let info = WindowInfo(
        windowID: windowID,
        ownerPID: ownerPID,
        bundleID: window.owningApplication?.bundleIdentifier,
        title: window.title,
        logicalFrame: LogicalFrame(
            x: Double(frame.origin.x),
            y: Double(frame.origin.y),
            width: Double(frame.width),
            height: Double(frame.height)
        ),
        onscreen: onscreen,
        minimized: onscreen ? false : nil,
        focused: nil,
        displayID: displayID(for: frame)
    )
    return WindowObservation(info: info, nativeWindow: window)
}

private func windowServerFrames() -> [CGWindowID: (frame: CGRect, onscreen: Bool)] {
    guard let values = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] else {
        return [:]
    }
    var frames: [CGWindowID: (frame: CGRect, onscreen: Bool)] = [:]
    for value in values {
        guard let number = (value[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
              let bounds = value[kCGWindowBounds as String] as? NSDictionary,
              let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else {
            continue
        }
        let onscreen = (value[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false
        frames[CGWindowID(number)] = (frame: frame, onscreen: onscreen)
    }
    return frames
}

private func displayID(for frame: CGRect) -> UInt32? {
    var count: UInt32 = 0
    guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return nil }
    var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
    guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return nil }
    let center = CGPoint(x: frame.midX, y: frame.midY)
    return displays.first(where: { CGDisplayBounds($0).contains(center) }).flatMap(UInt32.init)
}
