import AppKit

@main
struct StatusWindowTests {
    static func main() {
        let view = PermissionStatusView()
        view.update(PermissionSnapshot(accessibility: .unknown, screenRecording: .unknown))
        precondition(view.accessibilityText == "Accessibility: unknown")
        precondition(view.screenRecordingText == "Screen Recording: unknown")

        view.update(PermissionSnapshot(accessibility: .granted, screenRecording: .unknown))
        precondition(view.accessibilityText == "Accessibility: granted")
        precondition(view.screenRecordingText == "Screen Recording: unknown")

        view.update(PermissionSnapshot(accessibility: .granted, screenRecording: .granted))
        precondition(view.accessibilityText == "Accessibility: granted")
        precondition(view.screenRecordingText == "Screen Recording: granted")

        print("StatusWindowTests passed")
    }
}
