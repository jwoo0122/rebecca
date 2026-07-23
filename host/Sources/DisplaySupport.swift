import CoreGraphics
import Foundation
import ScreenCaptureKit

struct DisplayInfo: Encodable, Equatable {
    let displayID: UInt32
    let logicalFrame: LogicalFrame
    let pixelSize: PixelSize
    let scaleFactor: Double
    let primary: Bool

    enum CodingKeys: String, CodingKey {
        case displayID = "display_id"
        case logicalFrame = "logical_frame"
        case pixelSize = "pixel_size"
        case scaleFactor = "scale_factor"
        case primary
    }
}

struct LogicalFrame: Encodable, Equatable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

struct PixelSize: Encodable, Equatable {
    let width: UInt32
    let height: UInt32
}

enum DisplayQueryError: Error {
    case permissionDenied
    case timedOut
    case failed(String)
}

func queryDisplays(deadline: UInt64 = UInt64.max) throws -> [DisplayInfo] {
    let content: SCShareableContent
    do {
        content = try queryShareableContent(deadline: deadline)
    } catch let error as ScreenCaptureQueryError {
        switch error {
        case .permissionDenied:
            throw DisplayQueryError.permissionDenied
        case .timedOut:
            throw DisplayQueryError.timedOut
        case let .failed(message):
            throw DisplayQueryError.failed(message)
        }
    }
    return try content.displays.map(displayInfo).sorted { $0.displayID < $1.displayID }
}

private func displayInfo(for display: SCDisplay) throws -> DisplayInfo {
    let displayID = display.displayID
    let frame = CGDisplayBounds(displayID)
    let pixelWidth = CGDisplayPixelsWide(displayID)
    let pixelHeight = CGDisplayPixelsHigh(displayID)
    guard frame.width > 0, frame.height > 0, pixelWidth > 0, pixelHeight > 0 else {
        throw DisplayQueryError.failed("Display \(displayID) returned invalid geometry.")
    }
    guard let displayID = UInt32(exactly: displayID),
          let width = UInt32(exactly: pixelWidth),
          let height = UInt32(exactly: pixelHeight) else {
        throw DisplayQueryError.failed("Display identifiers or dimensions exceed protocol limits.")
    }

    return DisplayInfo(
        displayID: displayID,
        logicalFrame: LogicalFrame(
            x: Double(frame.origin.x),
            y: Double(frame.origin.y),
            width: Double(frame.width),
            height: Double(frame.height)
        ),
        pixelSize: PixelSize(width: width, height: height),
        scaleFactor: max(Double(pixelWidth) / Double(frame.width), Double(pixelHeight) / Double(frame.height)),
        primary: displayID == CGMainDisplayID()
    )
}

func displayObservationFingerprint(_ displays: [DisplayInfo]) -> Data {
    let values = displays.sorted { $0.displayID < $1.displayID }.map { display in
        [
            String(display.displayID),
            String(display.logicalFrame.x),
            String(display.logicalFrame.y),
            String(display.logicalFrame.width),
            String(display.logicalFrame.height),
            String(display.pixelSize.width),
            String(display.pixelSize.height),
            String(display.scaleFactor),
            String(display.primary)
        ].joined(separator: "|")
    }
    return Data(values.joined(separator: "\n").utf8)
}
