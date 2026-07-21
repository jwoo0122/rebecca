import Foundation

/// TCC preflight APIs report a boolean. They cannot distinguish denied from
/// not-determined or restricted without prompting, so the Milestone 0 host
/// reports a non-granted result as unknown.
enum PermissionState: String, Codable {
    case granted
    case unknown
}

struct PermissionSnapshot: Equatable {
    let accessibility: PermissionState
    let screenRecording: PermissionState
}

final class PermissionStatusTracker {
    private let provider: () -> PermissionSnapshot
    private var previousSnapshot: PermissionSnapshot?

    init(provider: @escaping () -> PermissionSnapshot) {
        self.provider = provider
    }

    func refresh() -> PermissionSnapshot? {
        let snapshot = provider()
        guard snapshot != previousSnapshot else { return nil }
        previousSnapshot = snapshot
        return snapshot
    }
}

func permissionState(isGranted: Bool) -> PermissionState {
    isGranted ? .granted : .unknown
}
