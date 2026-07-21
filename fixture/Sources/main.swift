import AppKit

private final class CaptureSurfaceView: NSView {
    override var isOpaque: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedRed: 0.10, green: 0.16, blue: 0.24, alpha: 1.0).setFill()
        dirtyRect.fill()
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

private final class TableDataSource: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    private let rows: [(String, String)] = [
        ("Alpha", "100"),
        ("Beta", "200"),
        ("Gamma", "300"),
    ]

    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = tableColumn?.identifier.rawValue ?? ""
        let text = id == "Name" ? rows[row].0 : rows[row].1
        let cell = NSTextField(labelWithString: text)
        cell.identifier = NSUserInterfaceItemIdentifier("TableCell")
        return cell
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate, NSTextFieldDelegate {
    private var window: NSWindow!
    private var statusLabel: NSTextField!
    private var textField: NSTextField!
    private var tableDataSource: TableDataSource!
    private var modalSheet: NSWindow?

    @objc private func testButtonClicked() {
        statusLabel.stringValue = "Status: Button Clicked"
    }

    @objc private func showModal() {
        let sheet = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 150),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        sheet.title = "Modal"

        let closeButton = NSButton(title: "Close Modal", target: self, action: #selector(closeModal))
        closeButton.setAccessibilityIdentifier("fixture-close-modal")
        closeButton.setAccessibilityLabel("Close Modal")
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        sheet.contentView!.addSubview(closeButton)

        NSLayoutConstraint.activate([
            closeButton.centerXAnchor.constraint(equalTo: sheet.contentView!.centerXAnchor),
            closeButton.centerYAnchor.constraint(equalTo: sheet.contentView!.centerYAnchor),
        ])

        modalSheet = sheet
        window.beginSheet(sheet, completionHandler: nil)
    }

    @objc private func closeModal() {
        guard let sheet = modalSheet else { return }
        window.endSheet(sheet)
        modalSheet = nil
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField, field == textField else { return }
        statusLabel.stringValue = "Status: Text Changed: \(field.stringValue)"
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let contentView = NSView()

        let titleLabel = NSTextField(labelWithString: "Rebecca Fixture")
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        titleLabel.setAccessibilityIdentifier("fixture-title")

        statusLabel = NSTextField(labelWithString: "Status: Ready")
        statusLabel.setAccessibilityIdentifier("fixture-status")

        let captureSurface = CaptureSurfaceView()
        captureSurface.setAccessibilityElement(true)
        captureSurface.setAccessibilityRole(.group)
        captureSurface.setAccessibilityLabel("Capture Surface")
        captureSurface.setAccessibilityIdentifier("fixture-capture-surface")

        let testButton = NSButton(title: "Test Button", target: self, action: #selector(testButtonClicked))
        testButton.setAccessibilityIdentifier("fixture-button")
        testButton.setAccessibilityLabel("Test Button")

        let disabledButton = NSButton(title: "Disabled Button", target: nil, action: nil)
        disabledButton.isEnabled = false
        disabledButton.setAccessibilityIdentifier("fixture-disabled-button")
        disabledButton.setAccessibilityLabel("Disabled Button")

        textField = NSTextField()
        textField.placeholderString = "Test Input"
        textField.setAccessibilityLabel("Test Input")
        textField.setAccessibilityIdentifier("fixture-text-field")
        textField.delegate = self

        let secureField = NSSecureTextField()
        secureField.placeholderString = "Secure Input"
        secureField.setAccessibilityIdentifier("fixture-secure-field")
        secureField.setAccessibilityLabel("Secure Input")

        let checkbox = NSButton(checkboxWithTitle: "Toggle", target: nil, action: nil)
        checkbox.setAccessibilityIdentifier("fixture-checkbox")
        checkbox.setAccessibilityLabel("Toggle")

        let slider = NSSlider(value: 50, minValue: 0, maxValue: 100, target: nil, action: nil)
        slider.setAccessibilityIdentifier("fixture-slider")
        slider.setAccessibilityLabel("Volume")

        let showModalButton = NSButton(title: "Show Modal", target: self, action: #selector(showModal))
        showModalButton.setAccessibilityIdentifier("fixture-show-modal")
        showModalButton.setAccessibilityLabel("Show Modal")

        // Scroll view with multi-line labels (400pt+ content)
        let scrollView = NSScrollView()
        scrollView.setAccessibilityIdentifier("fixture-scroll-view")
        scrollView.setAccessibilityLabel("Scroll View")
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.borderType = .bezelBorder

        let scrollDocView = FlippedView()
        var dy: CGFloat = 8
        for i in 1...12 {
            let line = NSTextField(labelWithString: "Line \(i): Lorem ipsum dolor sit amet, consectetur adipiscing elit.")
            line.font = .systemFont(ofSize: 13)
            line.frame = NSRect(x: 8, y: dy, width: 300, height: 32)
            scrollDocView.addSubview(line)
            dy += 36
        }
        scrollDocView.frame = NSRect(x: 0, y: 0, width: 334, height: dy)
        scrollView.documentView = scrollDocView

        // Multiline editor (NSTextView in NSScrollView)
        let multilineScrollView = NSScrollView()
        multilineScrollView.setAccessibilityIdentifier("fixture-multiline")
        multilineScrollView.setAccessibilityLabel("Multiline Editor")
        multilineScrollView.hasVerticalScroller = true
        multilineScrollView.autohidesScrollers = false
        multilineScrollView.borderType = .bezelBorder

        let textView = NSTextView()
        textView.font = .systemFont(ofSize: 13)
        textView.string = "Multiline editor content.\nEdit this text.\nLine three for testing."
        textView.setAccessibilityIdentifier("fixture-multiline")
        textView.setAccessibilityLabel("Multiline Editor")
        multilineScrollView.documentView = textView

        // Table (NSTableView with 2 columns, 3 rows)
        let tableScrollView = NSScrollView()
        tableScrollView.hasVerticalScroller = true
        tableScrollView.borderType = .bezelBorder
        tableScrollView.setAccessibilityIdentifier("fixture-table")
        tableScrollView.setAccessibilityLabel("Table")

        let tableView = NSTableView()
        tableView.setAccessibilityIdentifier("fixture-table")
        tableView.setAccessibilityLabel("Table")

        let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Name"))
        nameColumn.title = "Name"
        let valueColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Value"))
        valueColumn.title = "Value"
        tableView.addTableColumn(nameColumn)
        tableView.addTableColumn(valueColumn)

        tableDataSource = TableDataSource()
        tableView.dataSource = tableDataSource
        tableView.delegate = tableDataSource
        tableView.reloadData()
        tableScrollView.documentView = tableView

        let allViews: [NSView] = [titleLabel, testButton, disabledButton, textField, secureField,
                     checkbox, slider, showModalButton,
                     scrollView, tableScrollView,
                     multilineScrollView, captureSurface,
                     statusLabel]
        for view in allViews {
            view.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(view)
        }

        NSLayoutConstraint.activate([
            // Title
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            // Row 1: buttons + fields
            testButton.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            testButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),

            disabledButton.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            disabledButton.leadingAnchor.constraint(equalTo: testButton.trailingAnchor, constant: 8),

            textField.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            textField.leadingAnchor.constraint(equalTo: disabledButton.trailingAnchor, constant: 8),
            textField.widthAnchor.constraint(equalToConstant: 120),

            secureField.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            secureField.leadingAnchor.constraint(equalTo: textField.trailingAnchor, constant: 8),
            secureField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            // Row 2: checkbox + slider + modal button
            checkbox.topAnchor.constraint(equalTo: testButton.bottomAnchor, constant: 12),
            checkbox.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),

            slider.topAnchor.constraint(equalTo: testButton.bottomAnchor, constant: 16),
            slider.leadingAnchor.constraint(equalTo: checkbox.trailingAnchor, constant: 16),
            slider.widthAnchor.constraint(equalToConstant: 160),

            showModalButton.topAnchor.constraint(equalTo: testButton.bottomAnchor, constant: 12),
            showModalButton.leadingAnchor.constraint(equalTo: slider.trailingAnchor, constant: 16),
            showModalButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            // Left column top: scroll view
            scrollView.topAnchor.constraint(equalTo: checkbox.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            scrollView.widthAnchor.constraint(equalToConstant: 334),
            scrollView.heightAnchor.constraint(equalToConstant: 140),

            // Right column top: table
            tableScrollView.topAnchor.constraint(equalTo: checkbox.bottomAnchor, constant: 12),
            tableScrollView.leadingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: 12),
            tableScrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            tableScrollView.heightAnchor.constraint(equalToConstant: 140),

            // Left column bottom: multiline editor
            multilineScrollView.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 12),
            multilineScrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            multilineScrollView.widthAnchor.constraint(equalToConstant: 334),
            multilineScrollView.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -16),

            // Right column bottom: capture surface
            captureSurface.topAnchor.constraint(equalTo: tableScrollView.bottomAnchor, constant: 12),
            captureSurface.leadingAnchor.constraint(equalTo: multilineScrollView.trailingAnchor, constant: 12),
            captureSurface.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            captureSurface.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -16),

            // Status
            statusLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            statusLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),
        ])

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
            styleMask: [.titled, .resizable, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Rebecca Fixture"
        window.contentView = contentView
        window.setContentSize(NSSize(width: 720, height: 520))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}

@main
private struct RebeccaFixture {
    static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
    }
}
