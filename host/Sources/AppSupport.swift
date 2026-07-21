import AppKit

struct AppInfo: Encodable, Equatable {
    let pid: UInt32
    let bundleID: String?
    let name: String?
    let executableURL: String?
    let active: Bool
    let hidden: Bool

    enum CodingKeys: String, CodingKey {
        case pid
        case bundleID = "bundle_id"
        case name
        case executableURL = "executable_url"
        case active
        case hidden
    }
}

func queryApps() -> [AppInfo] {
    NSWorkspace.shared.runningApplications
        .filter { $0.processIdentifier > 0 }
        .sorted { $0.processIdentifier < $1.processIdentifier }
        .map { app in
            AppInfo(
                pid: UInt32(app.processIdentifier),
                bundleID: app.bundleIdentifier,
                name: app.localizedName,
                executableURL: app.executableURL?.path,
                active: app.isActive,
                hidden: app.isHidden
            )
        }
}
