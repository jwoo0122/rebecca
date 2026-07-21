import Foundation
import ScreenCaptureKit

// ScreenCaptureKit permission and content enumeration are shared by displays,
// windows, and capture requests. The socket worker waits only within the
// existing native I/O timeout.
enum ScreenCaptureQueryError: Error {
    case permissionDenied
    case timedOut
    case failed(String)
}

func queryShareableContent(deadline: UInt64 = UInt64.max) throws -> SCShareableContent {
    guard CGPreflightScreenCaptureAccess() else {
        throw ScreenCaptureQueryError.permissionDenied
    }

    let result = ShareableContentResult()
    let semaphore = DispatchSemaphore(value: 0)
    SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: false) { content, error in
        defer { semaphore.signal() }
        if let error {
            result.set(.failure(.failed(error.localizedDescription)))
            return
        }
        guard let content else {
            result.set(.failure(.failed("ScreenCaptureKit returned no shareable content.")))
            return
        }
        result.set(.success(content))
    }

    guard deadline == UInt64.max || deadline > DispatchTime.now().uptimeNanoseconds else {
        throw ScreenCaptureQueryError.timedOut
    }
    let timeout = deadline == UInt64.max
        ? DispatchTime.now() + .seconds(socketTimeoutSeconds)
        : DispatchTime(uptimeNanoseconds: deadline)
    guard semaphore.wait(timeout: timeout) == .success else {
        throw ScreenCaptureQueryError.timedOut
    }
    guard let value = result.get() else {
        throw ScreenCaptureQueryError.failed("ScreenCaptureKit did not return a result.")
    }
    return try value.get()
}

private final class ShareableContentResult: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Result<SCShareableContent, ScreenCaptureQueryError>?

    func set(_ value: Result<SCShareableContent, ScreenCaptureQueryError>) {
        lock.lock()
        defer { lock.unlock() }
        self.value = value
    }

    func get() -> Result<SCShareableContent, ScreenCaptureQueryError>? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
