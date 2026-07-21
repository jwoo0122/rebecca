import Foundation

@main
struct PermissionStateTests {
    static func main() {
        precondition(permissionState(isGranted: true) == .granted)
        precondition(permissionState(isGranted: false) == .unknown)

        var current = PermissionSnapshot(accessibility: .unknown, screenRecording: .unknown)
        let tracker = PermissionStatusTracker { current }
        precondition(tracker.refresh() == current)
        precondition(tracker.refresh() == nil)

        current = PermissionSnapshot(accessibility: .granted, screenRecording: .unknown)
        precondition(tracker.refresh() == current)
        current = PermissionSnapshot(accessibility: .granted, screenRecording: .granted)
        precondition(tracker.refresh() == current)
        current = PermissionSnapshot(accessibility: .unknown, screenRecording: .granted)
        precondition(tracker.refresh() == current)
        precondition(tracker.refresh() == nil)

        print("PermissionStateTests passed")
    }
}
