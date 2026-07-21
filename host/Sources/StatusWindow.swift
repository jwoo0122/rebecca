import AppKit

final class PermissionStatusView {
    let stack: NSStackView
    private let accessibilityLabel: NSTextField
    private let screenRecordingLabel: NSTextField

    var accessibilityText: String { accessibilityLabel.stringValue }
    var screenRecordingText: String { screenRecordingLabel.stringValue }

    init() {
        accessibilityLabel = NSTextField(labelWithString: "")
        screenRecordingLabel = NSTextField(labelWithString: "")
        let serviceLabel = NSTextField(labelWithString: "Service: running")
        stack = NSStackView(views: [accessibilityLabel, screenRecordingLabel, serviceLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
    }

    func update(_ snapshot: PermissionSnapshot) {
        accessibilityLabel.stringValue = "Accessibility: \(snapshot.accessibility.rawValue)"
        screenRecordingLabel.stringValue = "Screen Recording: \(snapshot.screenRecording.rawValue)"
    }
}
