import Darwin
import Foundation

@main
struct SocketSupportTests {
    static func main() throws {
        var sockets = [Int32](repeating: -1, count: 2)
        precondition(socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets) == 0)
        defer {
            close(sockets[0])
            close(sockets[1])
        }

        try setSocketTimeouts(sockets[0])
        precondition(timeout(on: sockets[0], option: SO_RCVTIMEO).tv_sec == socketTimeoutSeconds)
        precondition(timeout(on: sockets[0], option: SO_SNDTIMEO).tv_sec == socketTimeoutSeconds)
        print("SocketSupportTests passed")
    }

    private static func timeout(on fd: Int32, option: Int32) -> timeval {
        var timeout = timeval()
        var length = socklen_t(MemoryLayout<timeval>.size)
        precondition(getsockopt(fd, SOL_SOCKET, option, &timeout, &length) == 0)
        return timeout
    }
}
