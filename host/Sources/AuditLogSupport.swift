import Foundation

struct AuditEntry: Encodable {
    let timestamp: String
    let clientPID: Int32
    let clientExecutable: String
    let command: String
    let targetApp: String?
    let success: Bool
    let durationMs: Double
    let errorCode: String?

    enum CodingKeys: String, CodingKey {
        case timestamp
        case clientPID = "client_pid"
        case clientExecutable = "client_executable"
        case command
        case targetApp = "target_app"
        case success
        case durationMs = "duration_ms"
        case errorCode = "error_code"
    }
}

/// Returns the peer PID for a connected Unix socket.
/// On macOS, uses LOCAL_PEERCRED to get the PID.
func peerPID(for fd: Int32) -> Int32 {
    var pid: Int32 = 0
    var len = socklen_t(MemoryLayout<Int32>.size)
    let result = getsockopt(fd, SOL_LOCAL, LOCAL_PEERPID, &pid, &len)
    if result == 0 {
        return pid
    }
    return 0
}

/// Returns the executable path for a given PID.
func executablePath(for pid: Int32) -> String {
    var bufsize = Int(0)
    var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
    sysctl(&mib, UInt32(mib.count), nil, nil, nil, 0)
    bufsize = 4096
    var buffer = [CChar](repeating: 0, count: bufsize)
    if sysctl(&mib, UInt32(mib.count), &buffer, &bufsize, nil, 0) == 0 {
        // KERN_PROCARGS2 returns: argc as int32, then argv[0], then more
        // Skip the first 4 bytes (argc) and get the first string
        let start = 4
        let execPath = String(cString: Array(buffer[start..<bufsize]))
        return execPath
    }
    return "<unknown>"
}

/// Audit logger that writes structured JSON lines to a log file.
final class AuditLogger {
    private lazy var logURL: URL = {
        let runtimeDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Rebecca/runtime", isDirectory: true)
        try? FileManager.default.createDirectory(at: runtimeDir, withIntermediateDirectories: true)
        return runtimeDir.appendingPathComponent("audit.log")
    }()
    private let queue = DispatchQueue(label: "audit-logger")
    private lazy var dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    func log(
        clientPID: Int32,
        clientExecutable: String,
        command: String,
        targetApp: String?,
        success: Bool,
        durationMs: Double,
        errorCode: String?
    ) {
        queue.async { [self] in
            let entry = AuditEntry(
                timestamp: dateFormatter.string(from: Date()),
                clientPID: clientPID,
                clientExecutable: clientExecutable,
                command: command,
                targetApp: targetApp,
                success: success,
                durationMs: durationMs,
                errorCode: errorCode
            )
            guard let data = try? JSONEncoder().encode(entry) else { return }
            var line = data
            line.append(0x0A) // newline
            if let handle = try? FileHandle(forWritingTo: logURL) {
                handle.seekToEndOfFile()
                handle.write(line)
                handle.closeFile()
            } else {
                try? line.write(to: logURL)
            }
        }
    }
}
