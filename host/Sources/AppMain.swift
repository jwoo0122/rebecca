import AppKit
import ApplicationServices
import CoreGraphics
import Darwin
import Foundation

private let protocolVersion = 1
private let maximumFrameBytes = 64 * 1024
private let hostVersion = "0.1.0"
private let responseReserveNanoseconds: UInt64 = 100_000_000

private struct Request: Decodable {
    let protocolVersion: Int
    let requestID: String
    let command: String
    let arguments: [String: JSONValue]

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case requestID = "request_id"
        case command
        case arguments
    }

    init(from decoder: Decoder) throws {
        let keys = try decoder.container(keyedBy: AnyCodingKey.self).allKeys
        guard keys.allSatisfy({ CodingKeys(rawValue: $0.stringValue) != nil }) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Unknown request property.")
            )
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        protocolVersion = try container.decode(Int.self, forKey: .protocolVersion)
        requestID = try container.decode(String.self, forKey: .requestID)
        command = try container.decode(String.self, forKey: .command)
        arguments = try container.decode([String: JSONValue].self, forKey: .arguments)
        guard !requestID.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .requestID,
                in: container,
                debugDescription: "request_id must not be empty."
            )
        }
    }
}

private struct AnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

private enum JSONValue: Decodable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: JSONValue].self)) }
    }

    var stringValue: String? {
        guard case let .string(value) = self else { return nil }
        return value
    }

    var numberValue: Double? {
        guard case let .number(value) = self else { return nil }
        return value
    }

    var boolValue: Bool? {
        guard case let .bool(value) = self else { return nil }
        return value
    }

    var uint32Value: UInt32? {
        guard case let .number(value) = self,
              value.isFinite,
              value >= 0,
              value.rounded() == value else { return nil }
        return UInt32(exactly: value)
    }
}

private struct Host: Encodable {
    let running: Bool
    let version: String
    let pid: Int32
}

private struct Permissions: Encodable {
    let accessibility: PermissionState
    let screenRecording: PermissionState

    enum CodingKeys: String, CodingKey {
        case accessibility
        case screenRecording = "screen_recording"
    }
}

private struct HostError: Encodable {
    let code: String
    let message: String
}

private struct Response: Encodable {
    let protocolVersion: Int
    let requestID: String
    let ok: Bool
    let host: Host?
    let permissions: Permissions?
    let emergencyStop: Bool?
    let error: HostError?

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case requestID = "request_id"
        case ok, host, permissions, error
        case emergencyStop = "emergency_stop"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(protocolVersion, forKey: .protocolVersion)
        try container.encode(requestID, forKey: .requestID)
        try container.encode(ok, forKey: .ok)
        try container.encodeIfPresent(host, forKey: .host)
        try container.encodeIfPresent(permissions, forKey: .permissions)
        try container.encodeIfPresent(emergencyStop, forKey: .emergencyStop)
        try container.encodeIfPresent(error, forKey: .error)
    }
}

private struct DisplaysResponse: Encodable {
    let protocolVersion: Int
    let requestID: String
    let ok: Bool
    let revision: UInt64?
    let displays: [DisplayInfo]?
    let error: HostError?

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case requestID = "request_id"
        case ok, revision, displays, error
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(protocolVersion, forKey: .protocolVersion)
        try container.encode(requestID, forKey: .requestID)
        try container.encode(ok, forKey: .ok)
        try container.encodeIfPresent(revision, forKey: .revision)
        try container.encodeIfPresent(displays, forKey: .displays)
        try container.encodeIfPresent(error, forKey: .error)
    }
}

private struct WindowsResponse: Encodable {
    let protocolVersion: Int
    let requestID: String
    let ok: Bool
    let revision: UInt64?
    let windows: [WindowInfo]?
    let error: HostError?

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case requestID = "request_id"
        case ok, revision, windows, error
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(protocolVersion, forKey: .protocolVersion)
        try container.encode(requestID, forKey: .requestID)
        try container.encode(ok, forKey: .ok)
        try container.encodeIfPresent(revision, forKey: .revision)
        try container.encodeIfPresent(windows, forKey: .windows)
        try container.encodeIfPresent(error, forKey: .error)
    }
}

private struct CaptureTarget: Encodable {
    let targetType: String
    let id: UInt32

    enum CodingKeys: String, CodingKey {
        case targetType = "type"
        case id
    }
}

private struct CaptureResponse: Encodable {
    let protocolVersion: Int
    let requestID: String
    let ok: Bool
    let path: String?
    let target: CaptureTarget?
    let pixelSize: PixelSize?
    let logicalFrame: LogicalFrame?
    let scaleFactor: Double?
    let revision: UInt64?
    let error: HostError?

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case requestID = "request_id"
        case ok, path, target, error, revision
        case pixelSize = "pixel_size"
        case logicalFrame = "logical_frame"
        case scaleFactor = "scale_factor"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(protocolVersion, forKey: .protocolVersion)
        try container.encode(requestID, forKey: .requestID)
        try container.encode(ok, forKey: .ok)
        try container.encodeIfPresent(path, forKey: .path)
        try container.encodeIfPresent(target, forKey: .target)
        try container.encodeIfPresent(pixelSize, forKey: .pixelSize)
        try container.encodeIfPresent(logicalFrame, forKey: .logicalFrame)
        try container.encodeIfPresent(scaleFactor, forKey: .scaleFactor)
        try container.encodeIfPresent(revision, forKey: .revision)
        try container.encodeIfPresent(error, forKey: .error)
    }
}

private struct AppsResponse: Encodable {
    let protocolVersion: Int
    let requestID: String
    let ok: Bool
    let revision: UInt64?
    let apps: [AppInfo]?
    let error: HostError?

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case requestID = "request_id"
        case ok, revision, apps, error
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(protocolVersion, forKey: .protocolVersion)
        try container.encode(requestID, forKey: .requestID)
        try container.encode(ok, forKey: .ok)
        try container.encodeIfPresent(revision, forKey: .revision)
        try container.encodeIfPresent(apps, forKey: .apps)
        try container.encodeIfPresent(error, forKey: .error)
    }
}

private struct FocusedResponse: Encodable {
    let protocolVersion: Int
    let requestID: String
    let ok: Bool
    let revision: UInt64?
    let activeApp: FocusedApp?
    let focusedWindow: FocusedWindow?
    let focusedElement: FocusedElement?
    let error: HostError?

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case requestID = "request_id"
        case ok, revision, error
        case activeApp = "active_app"
        case focusedWindow = "focused_window"
        case focusedElement = "focused_element"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(protocolVersion, forKey: .protocolVersion)
        try container.encode(requestID, forKey: .requestID)
        try container.encode(ok, forKey: .ok)
        try container.encodeIfPresent(revision, forKey: .revision)
        try container.encodeIfPresent(activeApp, forKey: .activeApp)
        try container.encodeIfPresent(focusedWindow, forKey: .focusedWindow)
        try container.encodeIfPresent(focusedElement, forKey: .focusedElement)
        try container.encodeIfPresent(error, forKey: .error)
    }
}

private struct TreeResponse: Encodable {
    let protocolVersion: Int
    let requestID: String
    let ok: Bool
    let revision: UInt64?
    let root: TreeNode?
    let truncated: Bool?
    let error: HostError?

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case requestID = "request_id"
        case ok, revision, root, truncated, error
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(protocolVersion, forKey: .protocolVersion)
        try container.encode(requestID, forKey: .requestID)
        try container.encode(ok, forKey: .ok)
        try container.encodeIfPresent(revision, forKey: .revision)
        try container.encodeIfPresent(root, forKey: .root)
        try container.encodeIfPresent(truncated, forKey: .truncated)
        try container.encodeIfPresent(error, forKey: .error)
    }
}

private struct FindResponse: Encodable {
    let protocolVersion: Int
    let requestID: String
    let ok: Bool
    let revision: UInt64?
    let results: [TreeNode]?
    let truncated: Bool?
    let error: HostError?

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case requestID = "request_id"
        case ok, revision, results, truncated, error
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(protocolVersion, forKey: .protocolVersion)
        try container.encode(requestID, forKey: .requestID)
        try container.encode(ok, forKey: .ok)
        try container.encodeIfPresent(revision, forKey: .revision)
        try container.encodeIfPresent(results, forKey: .results)
        try container.encodeIfPresent(truncated, forKey: .truncated)
        try container.encodeIfPresent(error, forKey: .error)
    }
}

private struct ActionResponse: Encodable {
    let protocolVersion: Int
    let requestID: String
    let ok: Bool
    let action: String?
    let executed: Bool?
    let method: String?
    let beforeRevision: UInt64?
    let afterRevision: UInt64?
    let error: HostError?

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case requestID = "request_id"
        case ok, action, executed, method
        case beforeRevision = "before_revision"
        case afterRevision = "after_revision"
        case error
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(protocolVersion, forKey: .protocolVersion)
        try container.encode(requestID, forKey: .requestID)
        try container.encode(ok, forKey: .ok)
        try container.encodeIfPresent(action, forKey: .action)
        try container.encodeIfPresent(executed, forKey: .executed)
        try container.encodeIfPresent(method, forKey: .method)
        try container.encodeIfPresent(beforeRevision, forKey: .beforeRevision)
        try container.encodeIfPresent(afterRevision, forKey: .afterRevision)
        try container.encodeIfPresent(error, forKey: .error)
    }
}

private final class SocketServer {
    private let socketPath: String
    private var listenFD: Int32 = -1
    private var ownsSocket = false
    private var ownedSocketDevice: dev_t?
    private var ownedSocketInode: ino_t?
    private var observationRevisionTracker = ObservationRevisionTracker()
    private var emergencyStopActive = false
    private let auditLogger = AuditLogger()
    private let elementCache = ElementCache()

    init(socketPath: String) {
        self.socketPath = socketPath
    }

    deinit { stop() }

    func start() throws {
        try createRuntimeDirectory()
        let startupLock = try acquireStartupLock()
        defer { close(startupLock) }
        try removeStaleSocket()

        listenFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listenFD >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno)!) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(socketPath.utf8) + [0]
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            throw NSError(domain: "Rebecca", code: 1, userInfo: [NSLocalizedDescriptionKey: "Socket path is too long"])
        }
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            bytes.withUnsafeBytes { source in
                destination.copyBytes(from: source)
            }
        }

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(listenFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno)!) }
        var metadata = stat()
        guard lstat(socketPath, &metadata) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno)!) }
        ownsSocket = true
        ownedSocketDevice = metadata.st_dev
        ownedSocketInode = metadata.st_ino
        guard chmod(socketPath, S_IRUSR | S_IWUSR) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno)!)
        }
        guard listen(listenFD, 16) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno)!) }
    }

    func run() {
        while listenFD >= 0 {
            let clientFD = accept(listenFD, nil, nil)
            guard clientFD >= 0 else { continue }
            defer { close(clientFD) }
            guard isCurrentUser(clientFD) else { continue }
            do {
                try setSocketTimeouts(clientFD)
            } catch {
                continue
            }
            handle(clientFD)
        }
    }

    func stop() {
        if listenFD >= 0 {
            close(listenFD)
            listenFD = -1
        }
        if ownsSocket {
            removeOwnedSocket()
            ownsSocket = false
            ownedSocketDevice = nil
            ownedSocketInode = nil
        }
    }

    private func createRuntimeDirectory() throws {
        let directory = (socketPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        guard chmod(directory, S_IRWXU) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno)!)
        }
    }

    private func acquireStartupLock() throws -> Int32 {
        let lockPath = socketPath + ".lock"
        let lockFD = open(lockPath, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard lockFD >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno)!) }
        guard flock(lockFD, LOCK_EX) == 0 else {
            let error = POSIXError(POSIXErrorCode(rawValue: errno)!)
            close(lockFD)
            throw error
        }
        return lockFD
    }

    private func removeStaleSocket() throws {
        var metadata = stat()
        guard lstat(socketPath, &metadata) == 0 else {
            if errno == ENOENT { return }
            throw POSIXError(POSIXErrorCode(rawValue: errno)!)
        }
        guard (metadata.st_mode & S_IFMT) == S_IFSOCK else {
            throw NSError(
                domain: "Rebecca",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Refusing to replace non-socket path at \(socketPath)"]
            )
        }
        guard !socketIsActive(at: socketPath) else {
            throw NSError(
                domain: "Rebecca",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Rebecca host is already active at \(socketPath)"]
            )
        }

        let stagingDirectory = try createPrivateStagingDirectory()
        defer { _ = rmdir(stagingDirectory) }

        try runStaleSocketTestHook()
        let stagedPath = stagingDirectory + "/entry"
        guard rename(socketPath, stagedPath) == 0 else {
            if errno == ENOENT { return }
            throw POSIXError(POSIXErrorCode(rawValue: errno)!)
        }

        guard lstat(stagedPath, &metadata) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno)!)
        }
        guard (metadata.st_mode & S_IFMT) == S_IFSOCK else {
            try restoreStagedEntry(stagedPath)
            throw NSError(
                domain: "Rebecca",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Refusing to replace non-socket path at \(socketPath)"]
            )
        }
        guard !socketIsActive(at: stagedPath) else {
            try restoreStagedEntry(stagedPath)
            throw NSError(
                domain: "Rebecca",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Rebecca host is already active at \(socketPath)"]
            )
        }
        guard unlink(stagedPath) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno)!)
        }
    }

    private func createPrivateStagingDirectory() throws -> String {
        let runtimeDirectory = (socketPath as NSString).deletingLastPathComponent
        var stagingTemplate = Array((runtimeDirectory + "/.stale-socket.XXXXXX").utf8CString)
        guard let stagingDirectoryPointer = mkdtemp(&stagingTemplate) else {
            throw POSIXError(POSIXErrorCode(rawValue: errno)!)
        }
        let stagingDirectory = String(cString: stagingDirectoryPointer)
        guard chmod(stagingDirectory, S_IRWXU) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno)!)
        }
        return stagingDirectory
    }

    private func removeOwnedSocket() {
        guard let device = ownedSocketDevice,
              let inode = ownedSocketInode,
              let stagingDirectory = try? createPrivateStagingDirectory() else {
            return
        }
        defer { _ = rmdir(stagingDirectory) }

        let stagedPath = stagingDirectory + "/entry"
        guard rename(socketPath, stagedPath) == 0 else { return }

        var metadata = stat()
        guard lstat(stagedPath, &metadata) == 0 else { return }
        guard (metadata.st_mode & S_IFMT) == S_IFSOCK,
              metadata.st_dev == device,
              metadata.st_ino == inode else {
            try? restoreStagedEntry(stagedPath)
            return
        }
        _ = unlink(stagedPath)
    }

    private func restoreStagedEntry(_ stagedPath: String) throws {
        guard renameatx_np(AT_FDCWD, stagedPath, AT_FDCWD, socketPath, UInt32(RENAME_EXCL)) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno)!)
        }
    }

    private func runStaleSocketTestHook() throws {
        #if HOST_TEST
        guard let replacementPath = ProcessInfo.processInfo.environment["COMPUTER_USE_TEST_STALE_SOCKET_REPLACEMENT_PATH"] else {
            return
        }
        guard rename(replacementPath, socketPath) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno)!)
        }
        #endif
    }

    private func socketIsActive(at path: String) -> Bool {
        let probeFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard probeFD >= 0 else { return true }
        defer { close(probeFD) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8) + [0]
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { return true }
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            bytes.withUnsafeBytes { source in
                destination.copyBytes(from: source)
            }
        }
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(probeFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if result == 0 { return true }
        return errno != ECONNREFUSED && errno != ENOENT
    }

    private func isCurrentUser(_ clientFD: Int32) -> Bool {
        var uid: uid_t = 0
        var gid: gid_t = 0
        return getpeereid(clientFD, &uid, &gid) == 0 && uid == geteuid()
    }

    private func operationDeadline(before deadline: UInt64) -> UInt64 {
        let now = DispatchTime.now().uptimeNanoseconds
        guard deadline > now + responseReserveNanoseconds else { return now }
        return deadline - responseReserveNanoseconds
    }

    private func handle(_ fd: Int32) {
        let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(socketTimeoutSeconds) * 1_000_000_000
        let clientPID = peerPID(for: fd)
        let clientExec = clientPID > 0 ? executablePath(for: clientPID) : "<unknown>"
        let startTime = DispatchTime.now().uptimeNanoseconds
        let payload: Data
        switch readFrame(fd, deadline: deadline) {
        case let .payload(frame):
            payload = frame
        case .invalidSize:
            writeResponse(Response(
                protocolVersion: protocolVersion,
                requestID: UUID().uuidString,
                ok: false,
                host: nil,
                permissions: nil,
                emergencyStop: nil,
                error: HostError(code: "invalid_input", message: "Invalid frame size.")
            ), to: fd, deadline: deadline)
            return
        case .closed:
            return
        }
        let decoder = JSONDecoder()
        guard let request = try? decoder.decode(Request.self, from: payload) else {
            writeResponse(Response(
                protocolVersion: protocolVersion,
                requestID: UUID().uuidString,
                ok: false,
                host: nil,
                permissions: nil,
                emergencyStop: nil,
                error: HostError(code: "invalid_input", message: "Invalid request JSON.")
            ), to: fd, deadline: deadline)
            return
        }
        guard request.protocolVersion == protocolVersion else {
            writeResponse(Response(
                protocolVersion: protocolVersion,
                requestID: request.requestID,
                ok: false,
                host: nil,
                permissions: nil,
                emergencyStop: nil,
                error: HostError(code: "protocol_mismatch", message: "Unsupported protocol version.")
            ), to: fd, deadline: deadline)
            return
        }
        guard !request.command.isEmpty else {
            writeResponse(Response(
                protocolVersion: protocolVersion,
                requestID: request.requestID,
                ok: false,
                host: nil,
                permissions: nil,
                emergencyStop: nil,
                error: HostError(code: "invalid_input", message: "command must not be empty.")
            ), to: fd, deadline: deadline)
            return
        }
        if request.command == "status" {
            handleStatus(request, to: fd, deadline: deadline)
            return
        }
        if request.command == "displays" {
            handleDisplays(request, to: fd, deadline: deadline)
            return
        }
        if request.command == "windows" {
            handleWindows(request, to: fd, deadline: deadline)
            return
        }
        if request.command == "capture" {
            handleCapture(request, to: fd, deadline: deadline)
            return
        }
        if request.command == "apps" {
            handleApps(request, to: fd, deadline: deadline)
            return
        }
        if request.command == "focused" {
            handleFocused(request, to: fd, deadline: deadline)
            return
        }
        if request.command == "tree" {
            handleTree(request, to: fd, deadline: deadline)
            return
        }
        if request.command == "find" {
            handleFind(request, to: fd, deadline: deadline)
            return
        }
        if request.command == "press" {
            handlePress(request, to: fd, deadline: deadline)
            return
        }
        if request.command == "set_value" {
            handleSetValue(request, to: fd, deadline: deadline)
            return
        }
        if request.command == "click" {
            handleClick(request, to: fd, deadline: deadline)
            return
        }
        if request.command == "type" {
            handleType(request, to: fd, deadline: deadline)
            return
        }
        if request.command == "key" {
            handleKey(request, to: fd, deadline: deadline)
            return
        }
        if request.command == "move" {
            handleMove(request, to: fd, deadline: deadline)
            return
        }
        if request.command == "scroll" {
            handleScroll(request, to: fd, deadline: deadline)
            return
        }
        if request.command == "drag" {
            handleDrag(request, to: fd, deadline: deadline)
            return
        }
        if request.command == "activate" {
            handleActivate(request, to: fd, deadline: deadline)
            return
        }
        if request.command == "window_move" {
            handleWindowMove(request, to: fd, deadline: deadline)
            return
        }
        if request.command == "window_resize" {
            handleWindowResize(request, to: fd, deadline: deadline)
            return
        }
        if request.command == "window_close" {
            handleWindowClose(request, to: fd, deadline: deadline)
            return
        }
        if request.command == "stop" {
            emergencyStopActive = true
            let response = ActionResponse(
                protocolVersion: protocolVersion,
                requestID: request.requestID,
                ok: true,
                action: "stop",
                executed: true,
                method: "emergency_stop",
                beforeRevision: elementCache.currentRevision,
                afterRevision: elementCache.currentRevision,
                error: nil
            )
            writeResponse(response, to: fd, deadline: deadline)
            return
        }
        if request.command == "resume" {
            emergencyStopActive = false
            let response = ActionResponse(
                protocolVersion: protocolVersion,
                requestID: request.requestID,
                ok: true,
                action: "resume",
                executed: true,
                method: "emergency_resume",
                beforeRevision: elementCache.currentRevision,
                afterRevision: elementCache.currentRevision,
                error: nil
            )
            writeResponse(response, to: fd, deadline: deadline)
            return
        }

        // Emergency stop check for mutating commands
        let mutatingCommands: Set<String> = [
            "press", "set_value", "click", "type", "key", "move", "scroll", "drag", "activate",
            "window_move", "window_resize", "window_close"
        ]
        if emergencyStopActive && mutatingCommands.contains(request.command) {
            writeFailure(
                "Emergency stop is active. Run 'resume' to allow mutating actions.",
                code: "emergency_stop",
                request: request, to: fd, deadline: deadline
            )
            return
        }

        writeResponse(Response(
            protocolVersion: protocolVersion,
            requestID: request.requestID,
            ok: false,
            host: nil,
            permissions: nil,
            emergencyStop: nil,
            error: HostError(code: "unsupported", message: "status, displays, windows, capture, apps, focused, tree, find, press, set_value, click, type, key, move, scroll, drag, activate, window_move, window_resize, window_close, stop, and resume are available.")
        ), to: fd, deadline: deadline)
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - startTime) / 1_000_000.0
        auditLogger.log(clientPID: clientPID, clientExecutable: clientExec, command: request.command, targetApp: nil, success: false, durationMs: elapsed, errorCode: "unsupported")
    }

    private func handleStatus(_ request: Request, to fd: Int32, deadline: UInt64) {
        let snapshot = currentPermissionSnapshot()
        let response = Response(
            protocolVersion: protocolVersion,
            requestID: request.requestID,
            ok: true,
            host: Host(running: true, version: hostVersion, pid: getpid()),
            permissions: Permissions(
                accessibility: snapshot.accessibility,
                screenRecording: snapshot.screenRecording
            ),
            emergencyStop: emergencyStopActive,
            error: nil
        )
        writeResponse(response, to: fd, deadline: deadline)
    }

    private func handleDisplays(_ request: Request, to fd: Int32, deadline: UInt64) {
        let operationDeadline = operationDeadline(before: deadline)
        guard request.arguments.isEmpty else {
            writeResponse(Response(
                protocolVersion: protocolVersion,
                requestID: request.requestID,
                ok: false,
                host: nil,
                permissions: nil,
                emergencyStop: nil,
                error: HostError(code: "invalid_input", message: "displays does not accept arguments.")
            ), to: fd, deadline: deadline)
            return
        }

        do {
            let displays = try queryDisplays(deadline: operationDeadline)
            let revision = try observationRevisionTracker.revision(
                for: .displays,
                fingerprint: observationFingerprint(displays)
            )
            writeResponse(DisplaysResponse(
                protocolVersion: protocolVersion,
                requestID: request.requestID,
                ok: true,
                revision: revision,
                displays: displays,
                error: nil
            ), to: fd, deadline: deadline)
        } catch let error as DisplayQueryError {
            let hostError: HostError
            switch error {
            case .permissionDenied:
                hostError = HostError(code: "permission_denied", message: "Screen Recording permission is required for displays.")
            case .timedOut:
                hostError = HostError(code: "timeout", message: "Timed out while querying displays.")
            case let .failed(message):
                hostError = HostError(code: "internal_error", message: message)
            }
            writeResponse(Response(
                protocolVersion: protocolVersion,
                requestID: request.requestID,
                ok: false,
                host: nil,
                permissions: nil,
                emergencyStop: nil,
                error: hostError
            ), to: fd, deadline: deadline)
        } catch {
            writeResponse(Response(
                protocolVersion: protocolVersion,
                requestID: request.requestID,
                ok: false,
                host: nil,
                permissions: nil,
                emergencyStop: nil,
                error: HostError(code: "internal_error", message: error.localizedDescription)
            ), to: fd, deadline: deadline)
        }
    }

    private func handleWindows(_ request: Request, to fd: Int32, deadline: UInt64) {
        let operationDeadline = operationDeadline(before: deadline)
        let unknownArguments = request.arguments.keys.filter { $0 != "app" }
        guard unknownArguments.isEmpty else {
            writeFailure("windows accepts only the optional app argument.", code: "invalid_input", request: request, to: fd, deadline: deadline)
            return
        }
        let bundleID: String?
        if let app = request.arguments["app"] {
            guard let value = app.stringValue, !value.isEmpty else {
                writeFailure("app must be a non-empty bundle identifier.", code: "invalid_input", request: request, to: fd, deadline: deadline)
                return
            }
            bundleID = value
        } else {
            bundleID = nil
        }

        do {
            let snapshot = try queryWindowSnapshot(deadline: operationDeadline)
            let revision = try observationRevisionTracker.revision(
                for: .windows,
                fingerprint: observationFingerprint(snapshot.infos)
            )
            let windows = snapshot.observations
                .filter { bundleID == nil || $0.info.bundleID == bundleID }
                .map(\.info)
            writeResponse(WindowsResponse(
                protocolVersion: protocolVersion,
                requestID: request.requestID,
                ok: true,
                revision: revision,
                windows: windows,
                error: nil
            ), to: fd, deadline: deadline)
        } catch let error as WindowQueryError {
            let mapped = windowError(error)
            writeFailure(mapped.message, code: mapped.code, request: request, to: fd, deadline: deadline)
        } catch {
            writeFailure(error.localizedDescription, code: "internal_error", request: request, to: fd, deadline: deadline)
        }
    }

    private func handleCapture(_ request: Request, to fd: Int32, deadline: UInt64) {
        let operationDeadline = operationDeadline(before: deadline)
        guard request.arguments.keys.allSatisfy({ $0 == "window_id" || $0 == "output" }),
              let windowID = request.arguments["window_id"]?.uint32Value,
              windowID > 0,
              let output = request.arguments["output"]?.stringValue,
              !output.isEmpty else {
            writeFailure("capture requires a positive window_id and output path.", code: "invalid_input", request: request, to: fd, deadline: deadline)
            return
        }
        guard output.hasPrefix("/"), output.lowercased().hasSuffix(".png") else {
            writeFailure("capture output must be an absolute .png path.", code: "invalid_input", request: request, to: fd, deadline: deadline)
            return
        }

        do {
            let snapshot = try queryWindowSnapshot(deadline: operationDeadline)
            let revision = try observationRevisionTracker.revision(
                for: .windows,
                fingerprint: observationFingerprint(snapshot.infos)
            )
            guard let target = snapshot.observations.first(where: { $0.info.windowID == windowID }) else {
                writeFailure("Window \(windowID) was not found.", code: "target_not_found", request: request, to: fd, deadline: deadline)
                return
            }
            guard !FileManager.default.fileExists(atPath: output) else {
                writeFailure("Capture output already exists.", code: "invalid_input", request: request, to: fd, deadline: deadline)
                return
            }
            let captured = try captureWindowImage(target.nativeWindow, deadline: operationDeadline)
            let frame = captured.logicalFrame
            let targetFrame = target.info.logicalFrame
            guard abs(frame.x - targetFrame.x) <= 1,
                  abs(frame.y - targetFrame.y) <= 1,
                  abs(frame.width - targetFrame.width) <= 1,
                  abs(frame.height - targetFrame.height) <= 1 else {
                throw CaptureSupportError.failed("Window frame changed during capture.")
            }
            let scaleX = Double(captured.image.width) / frame.width
            let scaleY = Double(captured.image.height) / frame.height
            guard scaleX.isFinite, scaleY.isFinite, scaleX > 0, scaleY > 0,
                  abs(scaleX - scaleY) <= 0.01,
                  abs(scaleX - captured.scaleFactor) <= 0.01,
                  abs(scaleY - captured.scaleFactor) <= 0.01 else {
                throw CaptureSupportError.failed("Capture dimensions do not match the window frame.")
            }
            try writePNGWithoutOverwriting(captured.image, to: output, deadline: operationDeadline)
            writeResponse(CaptureResponse(
                protocolVersion: protocolVersion,
                requestID: request.requestID,
                ok: true,
                path: output,
                target: CaptureTarget(targetType: "window", id: windowID),
                pixelSize: PixelSize(width: UInt32(captured.image.width), height: UInt32(captured.image.height)),
                logicalFrame: frame,
                scaleFactor: captured.scaleFactor,
                revision: revision,
                error: nil
            ), to: fd, deadline: deadline)
        } catch let error as WindowQueryError {
            let mapped = windowError(error)
            writeFailure(mapped.message, code: mapped.code, request: request, to: fd, deadline: deadline)
        } catch let error as CaptureSupportError {
            let mapped = captureError(error)
            writeFailure(mapped.message, code: mapped.code, request: request, to: fd, deadline: deadline)
        } catch {
            writeFailure(error.localizedDescription, code: "internal_error", request: request, to: fd, deadline: deadline)
        }
    }

    private func writeFailure(_ message: String, code: String, request: Request, to fd: Int32, deadline: UInt64) {
        writeResponse(Response(
            protocolVersion: protocolVersion,
            requestID: request.requestID,
            ok: false,
            host: nil,
            permissions: nil,
            emergencyStop: nil,
            error: HostError(code: code, message: message)
        ), to: fd, deadline: deadline)
    }

    private func windowError(_ error: WindowQueryError) -> (code: String, message: String) {
        switch error {
        case .permissionDenied:
            return ("permission_denied", "Screen Recording permission is required for windows.")
        case .timedOut:
            return ("timeout", "Timed out while querying windows.")
        case let .failed(message):
            return ("internal_error", message)
        }
    }

    private func captureError(_ error: CaptureSupportError) -> (code: String, message: String) {
        switch error {
        case .permissionDenied:
            return ("permission_denied", "Screen Recording permission is required for capture.")
        case .timedOut:
            return ("timeout", "Timed out while capturing the window.")
        case .outputExists:
            return ("invalid_input", "Capture output already exists.")
        case let .invalidOutput(message):
            return ("invalid_input", message)
        case let .failed(message):
            return ("internal_error", message)
        }
    }

    private func handleApps(_ request: Request, to fd: Int32, deadline: UInt64) {
        guard request.arguments.isEmpty else {
            writeFailure("apps does not accept arguments.", code: "invalid_input", request: request, to: fd, deadline: deadline)
            return
        }
        let apps = queryApps()
        let revision: UInt64
        do {
            revision = try observationRevisionTracker.revision(
                for: .windows,
                fingerprint: observationFingerprint(apps)
            )
        } catch {
            writeFailure(error.localizedDescription, code: "internal_error", request: request, to: fd, deadline: deadline)
            return
        }
        writeResponse(AppsResponse(
            protocolVersion: protocolVersion,
            requestID: request.requestID,
            ok: true,
            revision: revision,
            apps: apps,
            error: nil
        ), to: fd, deadline: deadline)
    }

    private func handleFocused(_ request: Request, to fd: Int32, deadline: UInt64) {
        guard request.arguments.isEmpty else {
            writeFailure("focused does not accept arguments.", code: "invalid_input", request: request, to: fd, deadline: deadline)
            return
        }
        let operationDeadline = operationDeadline(before: deadline)
        do {
            let (activeApp, focusedWindow, focusedElement) = try queryFocusedState(deadline: operationDeadline)
            let revision: UInt64
            do {
                revision = try observationRevisionTracker.revision(
                    for: .windows,
                    fingerprint: observationFingerprint(
                        FocusFingerprint(pid: activeApp.pid, bundleID: activeApp.bundleID, name: activeApp.name)
                    )
                )
            } catch {
                writeFailure(error.localizedDescription, code: "internal_error", request: request, to: fd, deadline: deadline)
                return
            }
            writeResponse(FocusedResponse(
                protocolVersion: protocolVersion,
                requestID: request.requestID,
                ok: true,
                revision: revision,
                activeApp: activeApp,
                focusedWindow: focusedWindow,
                focusedElement: focusedElement,
                error: nil
            ), to: fd, deadline: deadline)
        } catch let error as FocusQueryError {
            let code: String
            let message: String
            switch error {
            case .permissionDenied:
                code = "permission_denied"
                message = "Accessibility permission is required for focused."
            case let .failed(msg):
                code = "internal_error"
                message = msg
            }
            writeFailure(message, code: code, request: request, to: fd, deadline: deadline)
        } catch {
            writeFailure(error.localizedDescription, code: "internal_error", request: request, to: fd, deadline: deadline)
        }
    }

    private func handleTree(_ request: Request, to fd: Int32, deadline: UInt64) {
        let operationDeadline = operationDeadline(before: deadline)
        do {
            let (appRef, windowRef) = try resolveTreeTarget(request, deadline: operationDeadline)
            let config = try parseTreeConfig(request)
            let revision = try observationRevisionTracker.revision(
                for: .windows,
                fingerprint: observationFingerprint(TreeTargetFingerprint(appPid: axPid(appRef), windowTitle: windowRef.flatMap { axString($0, kAXTitleAttribute) }))
            )
            elementCache.beginRevision(revision)
            let result = try queryTree(appRef: appRef, windowRef: windowRef, config: config, cache: elementCache, deadline: operationDeadline)
            writeResponse(TreeResponse(
                protocolVersion: protocolVersion,
                requestID: request.requestID,
                ok: true,
                revision: revision,
                root: result.root,
                truncated: result.truncated,
                error: nil
            ), to: fd, deadline: deadline)
        } catch let error as TreeQueryError {
            writeFailure(treeError(error).message, code: treeError(error).code, request: request, to: fd, deadline: deadline)
        } catch let error as FocusQueryError {
            writeFailure(focusError(error).message, code: focusError(error).code, request: request, to: fd, deadline: deadline)
        } catch {
            writeFailure(error.localizedDescription, code: "internal_error", request: request, to: fd, deadline: deadline)
        }
    }

    private func handleFind(_ request: Request, to fd: Int32, deadline: UInt64) {
        let operationDeadline = operationDeadline(before: deadline)
        do {
            let (appRef, windowRef) = try resolveTreeTarget(request, deadline: operationDeadline)
            let config = try parseTreeConfig(request)
            let condition = try parseFindCondition(request)
            let revision = try observationRevisionTracker.revision(
                for: .windows,
                fingerprint: observationFingerprint(TreeTargetFingerprint(appPid: axPid(appRef), windowTitle: windowRef.flatMap { axString($0, kAXTitleAttribute) }))
            )
            elementCache.beginRevision(revision)
            let result = try findInTree(appRef: appRef, windowRef: windowRef, condition: condition, config: config, cache: elementCache, deadline: operationDeadline)
            writeResponse(FindResponse(
                protocolVersion: protocolVersion,
                requestID: request.requestID,
                ok: true,
                revision: revision,
                results: result.results,
                truncated: result.truncated,
                error: nil
            ), to: fd, deadline: deadline)
        } catch let error as TreeQueryError {
            writeFailure(treeError(error).message, code: treeError(error).code, request: request, to: fd, deadline: deadline)
        } catch let error as FocusQueryError {
            writeFailure(focusError(error).message, code: focusError(error).code, request: request, to: fd, deadline: deadline)
        } catch {
            writeFailure(error.localizedDescription, code: "internal_error", request: request, to: fd, deadline: deadline)
        }
    }

    private func resolveTreeTarget(_ request: Request, deadline: UInt64) throws -> (AXUIElement, AXUIElement?) {
        let hasWindow = request.arguments["window"] != nil
        let hasApp = request.arguments["app"] != nil
        guard hasWindow != hasApp else {
            throw TreeQueryError.failed("Specify exactly one of window or app.")
        }

        if let windowValue = request.arguments["window"]?.stringValue {
            guard AXIsProcessTrusted() else {
                throw FocusQueryError.permissionDenied
            }
            if windowValue == "focused" {
                let systemWide = AXUIElementCreateSystemWide()
                var appRaw: CFTypeRef?
                guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &appRaw) == .success,
                      let appRef = appRaw else {
                    throw TreeQueryError.failed("Unable to determine focused application.")
                }
                let appElement = appRef as! AXUIElement
                var winRaw: CFTypeRef?
                if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &winRaw) == .success,
                   let winRef = winRaw {
                    return (appElement, (winRef as! AXUIElement))
                }
                return (appElement, nil)
            } else {
                throw TreeQueryError.failed("window must be 'focused' (numeric window_id not yet supported).")
            }
        }

        if let bundleID = request.arguments["app"]?.stringValue, !bundleID.isEmpty {
            guard AXIsProcessTrusted() else {
                throw FocusQueryError.permissionDenied
            }
            let app = NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == bundleID }
            guard let app, app.processIdentifier > 0 else {
                throw TreeQueryError.targetNotFound
            }
            let appRef = AXUIElementCreateApplication(app.processIdentifier)
            return (appRef, nil)
        }

        throw TreeQueryError.failed("Invalid tree target.")
    }

    private func parseTreeConfig(_ request: Request) throws -> TreeTraversalConfig {
        let depth: Int
        if let depthValue = request.arguments["depth"]?.uint32Value {
            depth = Int(depthValue)
        } else {
            depth = 8
        }
        guard depth >= 1, depth <= 64 else {
            throw TreeQueryError.failed("depth must be between 1 and 64.")
        }
        let visibleOnly = (request.arguments["visible_only"]?.boolValue) ?? false
        let condense = (request.arguments["condense_containers"]?.boolValue) ?? false
        return TreeTraversalConfig(maxDepth: depth, maxNodes: 10000, visibleOnly: visibleOnly, condenseContainers: condense)
    }

    private func parseFindCondition(_ request: Request) throws -> FindCondition {
        FindCondition(
            role: request.arguments["role"]?.stringValue,
            label: request.arguments["label"]?.stringValue,
            labelContains: request.arguments["label_contains"]?.stringValue,
            value: request.arguments["value"]?.stringValue,
            enabled: request.arguments["enabled"]?.boolValue,
            focused: request.arguments["focused"]?.boolValue
        )
    }

    private func treeError(_ error: TreeQueryError) -> (code: String, message: String) {
        switch error {
        case .permissionDenied:
            return ("permission_denied", "Accessibility permission is required for tree.")
        case .targetNotFound:
            return ("target_not_found", "Target application or window was not found.")
        case .timedOut:
            return ("timeout", "Timed out while traversing the accessibility tree.")
        case let .failed(message):
            return ("internal_error", message)
        }
    }

    private func focusError(_ error: FocusQueryError) -> (code: String, message: String) {
        switch error {
        case .permissionDenied:
            return ("permission_denied", "Accessibility permission is required.")
        case let .failed(message):
            return ("internal_error", message)
        }
    }

    private func handlePress(_ request: Request, to fd: Int32, deadline: UInt64) {
        guard let elementID = request.arguments["element"]?.stringValue, !elementID.isEmpty,
              let revisionValue = request.arguments["revision"]?.uint32Value else {
            writeFailure("press requires element and revision.", code: "invalid_input", request: request, to: fd, deadline: deadline)
            return
        }
        let providedRevision = UInt64(revisionValue)
        if providedRevision != elementCache.currentRevision {
            let mapped = actionError(.staleObservation(provided: providedRevision, current: elementCache.currentRevision))
            writeFailure(mapped.message, code: mapped.code, request: request, to: fd, deadline: deadline)
            return
        }
        guard let element = elementCache.resolve(elementID, revision: providedRevision) else {
            let mapped = actionError(.elementNotFound)
            writeFailure(mapped.message, code: mapped.code, request: request, to: fd, deadline: deadline)
            return
        }
        do {
            let result = try axPressElement(element, elementID: elementID, providedRevision: providedRevision, cache: elementCache, observationTracker: observationRevisionTracker, deadline: deadline)
            writeResponse(ActionResponse(
                protocolVersion: protocolVersion,
                requestID: request.requestID,
                ok: true,
                action: "press",
                executed: result.executed,
                method: result.method,
                beforeRevision: result.beforeRevision,
                afterRevision: result.afterRevision,
                error: nil
            ), to: fd, deadline: deadline)
        } catch let error as ActionError {
            let mapped = actionError(error)
            writeFailure(mapped.message, code: mapped.code, request: request, to: fd, deadline: deadline)
        } catch {
            writeFailure(error.localizedDescription, code: "internal_error", request: request, to: fd, deadline: deadline)
        }
    }

    private func handleSetValue(_ request: Request, to fd: Int32, deadline: UInt64) {
        guard let elementID = request.arguments["element"]?.stringValue, !elementID.isEmpty,
              let revisionValue = request.arguments["revision"]?.uint32Value,
              let value = request.arguments["value"]?.stringValue else {
            writeFailure("set_value requires element, revision, and value.", code: "invalid_input", request: request, to: fd, deadline: deadline)
            return
        }
        let providedRevision = UInt64(revisionValue)
        if providedRevision != elementCache.currentRevision {
            let mapped = actionError(.staleObservation(provided: providedRevision, current: elementCache.currentRevision))
            writeFailure(mapped.message, code: mapped.code, request: request, to: fd, deadline: deadline)
            return
        }
        guard let element = elementCache.resolve(elementID, revision: providedRevision) else {
            let mapped = actionError(.elementNotFound)
            writeFailure(mapped.message, code: mapped.code, request: request, to: fd, deadline: deadline)
            return
        }
        do {
            let result = try axSetValue(element, elementID: elementID, providedRevision: providedRevision, value: value, cache: elementCache, observationTracker: observationRevisionTracker, deadline: deadline)
            writeResponse(ActionResponse(
                protocolVersion: protocolVersion,
                requestID: request.requestID,
                ok: true,
                action: "set_value",
                executed: result.executed,
                method: result.method,
                beforeRevision: result.beforeRevision,
                afterRevision: result.afterRevision,
                error: nil
            ), to: fd, deadline: deadline)
        } catch let error as ActionError {
            let mapped = actionError(error)
            writeFailure(mapped.message, code: mapped.code, request: request, to: fd, deadline: deadline)
        } catch {
            writeFailure(error.localizedDescription, code: "internal_error", request: request, to: fd, deadline: deadline)
        }
    }

    private func handleClick(_ request: Request, to fd: Int32, deadline: UInt64) {
        do {
            let result: ActionResult
            if let elementID = request.arguments["element"]?.stringValue,
               let revValue = request.arguments["revision"]?.uint32Value {
                let rev = UInt64(revValue)
                if rev != elementCache.currentRevision {
                    let mapped = actionError(.staleObservation(provided: rev, current: elementCache.currentRevision))
                    writeFailure(mapped.message, code: mapped.code, request: request, to: fd, deadline: deadline)
                    return
                }
                guard let element = elementCache.resolve(elementID, revision: rev) else {
                    writeFailure("Element not found in current revision.", code: "target_not_found", request: request, to: fd, deadline: deadline)
                    return
                }
                result = try axPressElement(element, elementID: elementID, providedRevision: rev, cache: elementCache, observationTracker: observationRevisionTracker, deadline: deadline)
            } else if let x = request.arguments["x"]?.numberValue,
                      let y = request.arguments["y"]?.numberValue {
                let clickCount = Int(request.arguments["count"]?.numberValue ?? 1)
                try cgClick(x: x, y: y, clickCount: clickCount)
                let beforeRev = elementCache.currentRevision
                let afterRev = try observationRevisionTracker.revision(for: .windows, fingerprint: observationFingerprint(ActionFingerprint(action: "click", elementID: "coord")))
                elementCache.beginRevision(afterRev)
                result = ActionResult(executed: true, method: "cg_click", beforeRevision: beforeRev, afterRevision: afterRev)
            } else {
                writeFailure("click requires element+revision or x+y.", code: "invalid_input", request: request, to: fd, deadline: deadline)
                return
            }
            writeResponse(ActionResponse(protocolVersion: protocolVersion, requestID: request.requestID, ok: true, action: "click", executed: result.executed, method: result.method, beforeRevision: result.beforeRevision, afterRevision: result.afterRevision, error: nil), to: fd, deadline: deadline)
        } catch let error as ActionError {
            let mapped = actionError(error)
            writeFailure(mapped.message, code: mapped.code, request: request, to: fd, deadline: deadline)
        } catch {
            writeFailure(error.localizedDescription, code: "internal_error", request: request, to: fd, deadline: deadline)
        }
    }

    private func handleType(_ request: Request, to fd: Int32, deadline: UInt64) {
        guard let text = request.arguments["text"]?.stringValue, !text.isEmpty else {
            writeFailure("type requires text.", code: "invalid_input", request: request, to: fd, deadline: deadline)
            return
        }
        do {
            let result: ActionResult
            if let elementID = request.arguments["element"]?.stringValue,
               let revValue = request.arguments["revision"]?.uint32Value {
                let rev = UInt64(revValue)
                if rev != elementCache.currentRevision {
                    let mapped = actionError(.staleObservation(provided: rev, current: elementCache.currentRevision))
                    writeFailure(mapped.message, code: mapped.code, request: request, to: fd, deadline: deadline)
                    return
                }
                guard let element = elementCache.resolve(elementID, revision: rev) else {
                    writeFailure("Element not found in current revision.", code: "target_not_found", request: request, to: fd, deadline: deadline)
                    return
                }
                result = try axSetValue(element, elementID: elementID, providedRevision: rev, value: text, cache: elementCache, observationTracker: observationRevisionTracker, deadline: deadline)
            } else {
                try cgType(text)
                let beforeRev = elementCache.currentRevision
                let afterRev = try observationRevisionTracker.revision(for: .windows, fingerprint: observationFingerprint(ActionFingerprint(action: "type", elementID: "keyboard")))
                elementCache.beginRevision(afterRev)
                result = ActionResult(executed: true, method: "cg_type", beforeRevision: beforeRev, afterRevision: afterRev)
            }
            writeResponse(ActionResponse(protocolVersion: protocolVersion, requestID: request.requestID, ok: true, action: "type", executed: result.executed, method: result.method, beforeRevision: result.beforeRevision, afterRevision: result.afterRevision, error: nil), to: fd, deadline: deadline)
        } catch let error as ActionError {
            let mapped = actionError(error)
            writeFailure(mapped.message, code: mapped.code, request: request, to: fd, deadline: deadline)
        } catch {
            writeFailure(error.localizedDescription, code: "internal_error", request: request, to: fd, deadline: deadline)
        }
    }

    private func handleKey(_ request: Request, to fd: Int32, deadline: UInt64) {
        let chord: String
        if let c = request.arguments["chord"]?.stringValue { chord = c }
        else if let k = request.arguments["key"]?.stringValue { chord = k }
        else {
            writeFailure("key requires chord or key.", code: "invalid_input", request: request, to: fd, deadline: deadline)
            return
        }
        do {
            try cgKey(chord: chord)
            let beforeRev = elementCache.currentRevision
            let afterRev = try observationRevisionTracker.revision(for: .windows, fingerprint: observationFingerprint(ActionFingerprint(action: "key", elementID: chord)))
            elementCache.beginRevision(afterRev)
            writeResponse(ActionResponse(protocolVersion: protocolVersion, requestID: request.requestID, ok: true, action: "key", executed: true, method: "cg_key", beforeRevision: beforeRev, afterRevision: afterRev, error: nil), to: fd, deadline: deadline)
        } catch let error as ActionError {
            let mapped = actionError(error)
            writeFailure(mapped.message, code: mapped.code, request: request, to: fd, deadline: deadline)
        } catch {
            writeFailure(error.localizedDescription, code: "internal_error", request: request, to: fd, deadline: deadline)
        }
    }

    private func handleMove(_ request: Request, to fd: Int32, deadline: UInt64) {
        guard let x = request.arguments["x"]?.numberValue,
              let y = request.arguments["y"]?.numberValue else {
            writeFailure("move requires x and y.", code: "invalid_input", request: request, to: fd, deadline: deadline)
            return
        }
        do {
            try cgMove(x: x, y: y)
            let beforeRev = elementCache.currentRevision
            let afterRev = try observationRevisionTracker.revision(for: .windows, fingerprint: observationFingerprint(ActionFingerprint(action: "move", elementID: "coord")))
            elementCache.beginRevision(afterRev)
            writeResponse(ActionResponse(protocolVersion: protocolVersion, requestID: request.requestID, ok: true, action: "move", executed: true, method: "cg_move", beforeRevision: beforeRev, afterRevision: afterRev, error: nil), to: fd, deadline: deadline)
        } catch let error as ActionError {
            let mapped = actionError(error)
            writeFailure(mapped.message, code: mapped.code, request: request, to: fd, deadline: deadline)
        } catch {
            writeFailure(error.localizedDescription, code: "internal_error", request: request, to: fd, deadline: deadline)
        }
    }

    private func handleScroll(_ request: Request, to fd: Int32, deadline: UInt64) {
        let dx = request.arguments["dx"]?.numberValue ?? 0
        let dy = request.arguments["dy"]?.numberValue ?? 0
        if dx == 0 && dy == 0 {
            writeFailure("scroll requires dx or dy.", code: "invalid_input", request: request, to: fd, deadline: deadline)
            return
        }
        do {
            try cgScroll(dx: dx, dy: dy)
            let beforeRev = elementCache.currentRevision
            let afterRev = try observationRevisionTracker.revision(for: .windows, fingerprint: observationFingerprint(ActionFingerprint(action: "scroll", elementID: "coord")))
            elementCache.beginRevision(afterRev)
            writeResponse(ActionResponse(protocolVersion: protocolVersion, requestID: request.requestID, ok: true, action: "scroll", executed: true, method: "cg_scroll", beforeRevision: beforeRev, afterRevision: afterRev, error: nil), to: fd, deadline: deadline)
        } catch let error as ActionError {
            let mapped = actionError(error)
            writeFailure(mapped.message, code: mapped.code, request: request, to: fd, deadline: deadline)
        } catch {
            writeFailure(error.localizedDescription, code: "internal_error", request: request, to: fd, deadline: deadline)
        }
    }

    private func handleDrag(_ request: Request, to fd: Int32, deadline: UInt64) {
        guard let fromX = request.arguments["from_x"]?.numberValue,
              let fromY = request.arguments["from_y"]?.numberValue,
              let toX = request.arguments["to_x"]?.numberValue,
              let toY = request.arguments["to_y"]?.numberValue else {
            writeFailure("drag requires from_x, from_y, to_x, to_y.", code: "invalid_input", request: request, to: fd, deadline: deadline)
            return
        }
        let durationMs = request.arguments["duration_ms"]?.numberValue ?? 500
        do {
            try cgDrag(fromX: fromX, fromY: fromY, toX: toX, toY: toY, durationMs: durationMs)
            let beforeRev = elementCache.currentRevision
            let afterRev = try observationRevisionTracker.revision(for: .windows, fingerprint: observationFingerprint(ActionFingerprint(action: "drag", elementID: "coord")))
            elementCache.beginRevision(afterRev)
            writeResponse(ActionResponse(protocolVersion: protocolVersion, requestID: request.requestID, ok: true, action: "drag", executed: true, method: "cg_drag", beforeRevision: beforeRev, afterRevision: afterRev, error: nil), to: fd, deadline: deadline)
        } catch let error as ActionError {
            let mapped = actionError(error)
            writeFailure(mapped.message, code: mapped.code, request: request, to: fd, deadline: deadline)
        } catch {
            writeFailure(error.localizedDescription, code: "internal_error", request: request, to: fd, deadline: deadline)
        }
    }

    private func handleActivate(_ request: Request, to fd: Int32, deadline: UInt64) {
        guard let bundleID = request.arguments["app"]?.stringValue, !bundleID.isEmpty else {
            writeFailure("activate requires app (bundle ID).", code: "invalid_input", request: request, to: fd, deadline: deadline)
            return
        }
        do {
            try axActivateApp(bundleID: bundleID)
            let beforeRev = elementCache.currentRevision
            let afterRev = try observationRevisionTracker.revision(for: .windows, fingerprint: observationFingerprint(ActionFingerprint(action: "activate", elementID: bundleID)))
            elementCache.beginRevision(afterRev)
            writeResponse(ActionResponse(protocolVersion: protocolVersion, requestID: request.requestID, ok: true, action: "activate", executed: true, method: "ax_activate", beforeRevision: beforeRev, afterRevision: afterRev, error: nil), to: fd, deadline: deadline)
        } catch let error as ActionError {
            let mapped = actionError(error)
            writeFailure(mapped.message, code: mapped.code, request: request, to: fd, deadline: deadline)
        } catch {
            writeFailure(error.localizedDescription, code: "internal_error", request: request, to: fd, deadline: deadline)
        }
    }

    private func handleWindowMove(_ request: Request, to fd: Int32, deadline: UInt64) {
        guard let windowID = request.arguments["window_id"]?.uint32Value,
              let x = request.arguments["x"]?.numberValue,
              let y = request.arguments["y"]?.numberValue else {
            writeFailure("window_move requires window_id, x, y.", code: "invalid_input", request: request, to: fd, deadline: deadline)
            return
        }
        do {
            try axWindowMove(windowID: windowID, x: x, y: y, deadline: deadline)
            let beforeRev = elementCache.currentRevision
            let afterRev = try observationRevisionTracker.revision(for: .windows, fingerprint: observationFingerprint(ActionFingerprint(action: "window_move", elementID: "window_\(windowID)")))
            elementCache.beginRevision(afterRev)
            writeResponse(ActionResponse(protocolVersion: protocolVersion, requestID: request.requestID, ok: true, action: "window_move", executed: true, method: "ax_window_move", beforeRevision: beforeRev, afterRevision: afterRev, error: nil), to: fd, deadline: deadline)
        } catch let error as ActionError {
            let mapped = actionError(error)
            writeFailure(mapped.message, code: mapped.code, request: request, to: fd, deadline: deadline)
        } catch {
            writeFailure(error.localizedDescription, code: "internal_error", request: request, to: fd, deadline: deadline)
        }
    }

    private func handleWindowResize(_ request: Request, to fd: Int32, deadline: UInt64) {
        guard let windowID = request.arguments["window_id"]?.uint32Value,
              let width = request.arguments["width"]?.numberValue,
              let height = request.arguments["height"]?.numberValue else {
            writeFailure("window_resize requires window_id, width, height.", code: "invalid_input", request: request, to: fd, deadline: deadline)
            return
        }
        do {
            try axWindowResize(windowID: windowID, width: width, height: height, deadline: deadline)
            let beforeRev = elementCache.currentRevision
            let afterRev = try observationRevisionTracker.revision(for: .windows, fingerprint: observationFingerprint(ActionFingerprint(action: "window_resize", elementID: "window_\(windowID)")))
            elementCache.beginRevision(afterRev)
            writeResponse(ActionResponse(protocolVersion: protocolVersion, requestID: request.requestID, ok: true, action: "window_resize", executed: true, method: "ax_window_resize", beforeRevision: beforeRev, afterRevision: afterRev, error: nil), to: fd, deadline: deadline)
        } catch let error as ActionError {
            let mapped = actionError(error)
            writeFailure(mapped.message, code: mapped.code, request: request, to: fd, deadline: deadline)
        } catch {
            writeFailure(error.localizedDescription, code: "internal_error", request: request, to: fd, deadline: deadline)
        }
    }

    private func handleWindowClose(_ request: Request, to fd: Int32, deadline: UInt64) {
        guard let windowID = request.arguments["window_id"]?.uint32Value else {
            writeFailure("window_close requires window_id.", code: "invalid_input", request: request, to: fd, deadline: deadline)
            return
        }
        do {
            try axWindowClose(windowID: windowID, deadline: deadline)
            let beforeRev = elementCache.currentRevision
            let afterRev = try observationRevisionTracker.revision(for: .windows, fingerprint: observationFingerprint(ActionFingerprint(action: "window_close", elementID: "window_\(windowID)")))
            elementCache.beginRevision(afterRev)
            writeResponse(ActionResponse(protocolVersion: protocolVersion, requestID: request.requestID, ok: true, action: "window_close", executed: true, method: "ax_window_close", beforeRevision: beforeRev, afterRevision: afterRev, error: nil), to: fd, deadline: deadline)
        } catch let error as ActionError {
            let mapped = actionError(error)
            writeFailure(mapped.message, code: mapped.code, request: request, to: fd, deadline: deadline)
        } catch {
            writeFailure(error.localizedDescription, code: "internal_error", request: request, to: fd, deadline: deadline)
        }
    }

    private enum FrameReadResult {
        case payload(Data)
        case invalidSize
        case closed
    }

    private func readFrame(_ fd: Int32, deadline: UInt64) -> FrameReadResult {
        guard let header = readExactly(fd, count: 4, deadline: deadline) else { return .closed }
        let bytes = [UInt8](header)
        let length = (UInt32(bytes[0]) << 24)
            | (UInt32(bytes[1]) << 16)
            | (UInt32(bytes[2]) << 8)
            | UInt32(bytes[3])
        guard length > 0, length <= maximumFrameBytes else { return .invalidSize }
        guard let payload = readExactly(fd, count: Int(length), deadline: deadline) else { return .closed }
        return .payload(payload)
    }

    private func writeResponse<T: Encodable>(_ response: T, to fd: Int32, deadline: UInt64) {
        guard let payload = try? JSONEncoder().encode(response), payload.count <= maximumFrameBytes else { return }
        var length = UInt32(payload.count).bigEndian
        let wroteHeader = withUnsafeBytes(of: &length) { writeAll(fd, bytes: $0, deadline: deadline) }
        guard wroteHeader else { return }
        _ = payload.withUnsafeBytes { writeAll(fd, bytes: $0, deadline: deadline) }
    }

    private func readExactly(_ fd: Int32, count: Int, deadline: UInt64) -> Data? {
        var data = Data(count: count)
        let complete = data.withUnsafeMutableBytes { buffer -> Bool in
            var offset = 0
            while offset < count {
                guard DispatchTime.now().uptimeNanoseconds < deadline else { return false }
                let readCount = Darwin.read(fd, buffer.baseAddress!.advanced(by: offset), count - offset)
                if readCount <= 0 { return false }
                offset += readCount
            }
            return true
        }
        return complete ? data : nil
    }

    private func writeAll(_ fd: Int32, bytes: UnsafeRawBufferPointer, deadline: UInt64) -> Bool {
        var offset = 0
        while offset < bytes.count {
            guard DispatchTime.now().uptimeNanoseconds < deadline else { return false }
            let written = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
            if written <= 0 { return false }
            offset += written
        }
        return true
    }
}

private func currentPermissionSnapshot() -> PermissionSnapshot {
    PermissionSnapshot(
        accessibility: permissionState(isGranted: AXIsProcessTrusted()),
        screenRecording: permissionState(isGranted: CGPreflightScreenCaptureAccess())
    )
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var server: SocketServer?
    private var statusWindow: NSWindow?
    private var statusView: PermissionStatusView?
    private var permissionStatusTracker: PermissionStatusTracker?
    private var statusRefreshTimer: Timer?
    private var terminationSignal: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let server = SocketServer(socketPath: defaultSocketPath())
        do {
            try server.start()
            self.server = server
            showStatusWindow()
            installTerminationHandler()
            DispatchQueue.global(qos: .userInitiated).async { server.run() }
        } catch {
            fputs("Rebecca host failed to start: \(error)\n", stderr)
            exit(1)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusRefreshTimer?.invalidate()
        statusRefreshTimer = nil
        server?.stop()
    }

    private func defaultSocketPath() -> String {
        #if HOST_TEST
        return ProcessInfo.processInfo.environment["COMPUTER_USE_TEST_SOCKET_PATH"]!
        #else
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return home + "/Library/Application Support/Rebecca/runtime/control.sock"
        #endif
    }

    private func showStatusWindow() {
        let statusView = PermissionStatusView()
        self.statusView = statusView
        let stack = statusView.stack

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 150),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Rebecca Status"
        window.contentView = stack
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        statusWindow = window
        permissionStatusTracker = PermissionStatusTracker(provider: currentPermissionSnapshot)
        refreshPermissionStatus()
        statusRefreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshPermissionStatus()
        }
    }

    private func refreshPermissionStatus() {
        guard let snapshot = permissionStatusTracker?.refresh() else { return }
        statusView?.update(snapshot)
    }

    private func installTerminationHandler() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { NSApp.terminate(nil) }
        source.resume()
        terminationSignal = source
    }
}

@main
private struct RebeccaHost {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
