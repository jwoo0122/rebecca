import CoreGraphics
import Darwin
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

struct CapturedWindowImage {
    let image: CGImage
    let logicalFrame: LogicalFrame
    let scaleFactor: Double
}

enum CaptureSupportError: Error {
    case permissionDenied
    case timedOut
    case outputExists
    case invalidOutput(String)
    case failed(String)
}

func captureWindowImage(_ window: SCWindow, deadline: UInt64 = UInt64.max) throws -> CapturedWindowImage {
    guard CGPreflightScreenCaptureAccess() else {
        throw CaptureSupportError.permissionDenied
    }

    let filter = SCContentFilter(desktopIndependentWindow: window)
    let frame = window.frame
    let scale = max(Double(filter.pointPixelScale), 1.0)
    let width = max(Int(ceil(frame.width * scale)), 1)
    let height = max(Int(ceil(frame.height * scale)), 1)
    let configuration = SCStreamConfiguration()
    configuration.width = width
    configuration.height = height
    configuration.showsCursor = false
    configuration.ignoreShadowsSingleWindow = true
    configuration.shouldBeOpaque = true
    configuration.includeChildWindows = false

    let result = CapturedImageResult()
    let semaphore = DispatchSemaphore(value: 0)
    let task = Task {
        defer { semaphore.signal() }
        do {
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
            result.set(.success(image))
        } catch {
            result.set(.failure(.failed(error.localizedDescription)))
        }
    }

    guard deadline == UInt64.max || deadline > DispatchTime.now().uptimeNanoseconds else {
        task.cancel()
        throw CaptureSupportError.timedOut
    }
    let timeout = deadline == UInt64.max
        ? DispatchTime.now() + .seconds(socketTimeoutSeconds)
        : DispatchTime(uptimeNanoseconds: deadline)
    guard semaphore.wait(timeout: timeout) == .success else {
        task.cancel()
        throw CaptureSupportError.timedOut
    }
    guard let value = result.get() else {
        throw CaptureSupportError.failed("ScreenCaptureKit did not return a capture result.")
    }
    let image = try value.get()
    return CapturedWindowImage(
        image: image,
        logicalFrame: LogicalFrame(
            x: Double(frame.origin.x),
            y: Double(frame.origin.y),
            width: Double(frame.width),
            height: Double(frame.height)
        ),
        scaleFactor: scale
    )
}

func writePNGWithoutOverwriting(_ image: CGImage, to path: String, deadline: UInt64 = UInt64.max) throws {
    guard path.hasPrefix("/") else {
        throw CaptureSupportError.invalidOutput("Capture output path must be absolute.")
    }
    guard path.lowercased().hasSuffix(".png") else {
        throw CaptureSupportError.invalidOutput("Capture output path must end in .png.")
    }
    guard !FileManager.default.fileExists(atPath: path) else {
        throw CaptureSupportError.outputExists
    }

    guard deadline == UInt64.max || deadline > DispatchTime.now().uptimeNanoseconds else {
        throw CaptureSupportError.timedOut
    }
    let data = try pngData(from: image)
    guard deadline == UInt64.max || deadline > DispatchTime.now().uptimeNanoseconds else {
        throw CaptureSupportError.timedOut
    }
    let directory = (path as NSString).deletingLastPathComponent
    var template = Array((directory + "/.rebecca-capture.XXXXXX").utf8CString)
    var temporaryFD = mkstemp(&template)
    guard temporaryFD >= 0 else {
        throw CaptureSupportError.failed("Unable to create a temporary capture file.")
    }
    let temporaryPath = String(cString: template)
    var published = false
    defer {
        if temporaryFD >= 0 { close(temporaryFD) }
        if !published { _ = unlink(temporaryPath) }
    }

    try writeAll(data, to: temporaryFD)
    guard fsync(temporaryFD) == 0 else {
        throw CaptureSupportError.failed("Unable to flush the temporary capture file.")
    }
    let descriptorToClose = temporaryFD
    temporaryFD = -1
    guard close(descriptorToClose) == 0 else {
        throw CaptureSupportError.failed("Unable to close the temporary capture file.")
    }

    guard deadline == UInt64.max || deadline > DispatchTime.now().uptimeNanoseconds else {
        throw CaptureSupportError.timedOut
    }
    let renameResult = renameatx_np(
        AT_FDCWD,
        temporaryPath,
        AT_FDCWD,
        path,
        UInt32(RENAME_EXCL)
    )
    guard renameResult == 0 else {
        if errno == EEXIST { throw CaptureSupportError.outputExists }
        throw CaptureSupportError.failed("Unable to publish the capture file.")
    }
    published = true
}

private func pngData(from image: CGImage) throws -> Data {
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
        data,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        throw CaptureSupportError.failed("Unable to create a PNG destination.")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw CaptureSupportError.failed("Unable to finalize the PNG image.")
    }
    return data as Data
}

private func writeAll(_ data: Data, to fd: Int32) throws {
    try data.withUnsafeBytes { buffer in
        guard let baseAddress = buffer.baseAddress else {
            throw CaptureSupportError.failed("PNG data was empty.")
        }
        var offset = 0
        while offset < buffer.count {
            let written = Darwin.write(fd, baseAddress.advanced(by: offset), buffer.count - offset)
            guard written > 0 else {
                throw CaptureSupportError.failed("Unable to write the temporary capture file.")
            }
            offset += written
        }
    }
}

private final class CapturedImageResult: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Result<CGImage, CaptureSupportError>?

    func set(_ value: Result<CGImage, CaptureSupportError>) {
        lock.lock()
        defer { lock.unlock() }
        self.value = value
    }

    func get() -> Result<CGImage, CaptureSupportError>? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
