import Darwin
import Foundation

let socketTimeoutSeconds: Int = 2

func setSocketTimeouts(_ fd: Int32) throws {
    var timeout = timeval(tv_sec: socketTimeoutSeconds, tv_usec: 0)
    let timeoutLength = socklen_t(MemoryLayout<timeval>.size)
    guard setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, timeoutLength) == 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno)!)
    }
    guard setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, timeoutLength) == 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno)!)
    }
}
