import CoreGraphics
import Foundation

// MARK: - CGEvent click

func cgClick(x: Double, y: Double, button: CGMouseButton = .left, clickCount: Int = 1) throws {
    let point = CGPoint(x: x, y: y)
    let source = CGEventSource(stateID: .hidSystemState)

    for attempt in 0..<clickCount {
        let mouseDown = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: button)
        guard let down = mouseDown else {
            throw ActionError.failed("Failed to create mouse down event.")
        }
        down.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount - attempt))
        down.post(tap: .cghidEventTap)

        let mouseUp = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: button)
        guard let up = mouseUp else {
            throw ActionError.failed("Failed to create mouse up event.")
        }
        up.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount - attempt))
        up.post(tap: .cghidEventTap)

        if attempt < clickCount - 1 {
            usleep(50000) // 50ms between clicks
        }
    }
}

// MARK: - CGEvent move

func cgMove(x: Double, y: Double) throws {
    let point = CGPoint(x: x, y: y)
    let source = CGEventSource(stateID: .hidSystemState)
    let move = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)
    guard let event = move else {
        throw ActionError.failed("Failed to create mouse move event.")
    }
    event.post(tap: .cghidEventTap)
}

// MARK: - CGEvent scroll

func cgScroll(dx: Double, dy: Double) throws {
    let source = CGEventSource(stateID: .hidSystemState)
    if dy != 0 {
        let scroll = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 1, wheel1: Int32(dy), wheel2: 0, wheel3: 0)
        guard let event = scroll else {
            throw ActionError.failed("Failed to create vertical scroll event.")
        }
        event.post(tap: .cghidEventTap)
    }
    if dx != 0 {
        let scroll = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2, wheel1: 0, wheel2: Int32(dx), wheel3: 0)
        guard let event = scroll else {
            throw ActionError.failed("Failed to create horizontal scroll event.")
        }
        event.post(tap: .cghidEventTap)
    }
}

// MARK: - CGEvent key

private let keyMap: [String: CGKeyCode] = [
    "return": 0x24, "enter": 0x4c, "tab": 0x30, "space": 0x31,
    "delete": 0x33, "forwarddelete": 0x75, "escape": 0x35, "esc": 0x35,
    "command": 0x37, "cmd": 0x37, "shift": 0x38, "control": 0x3b, "ctrl": 0x3b,
    "option": 0x3a, "alt": 0x3a, "capslock": 0x39,
    "a": 0x00, "b": 0x0b, "c": 0x08, "d": 0x02, "e": 0x0e, "f": 0x03,
    "g": 0x05, "h": 0x04, "i": 0x22, "j": 0x26, "k": 0x28, "l": 0x25,
    "m": 0x2e, "n": 0x2d, "o": 0x1f, "p": 0x23, "q": 0x0c, "r": 0x0f,
    "s": 0x01, "t": 0x11, "u": 0x20, "v": 0x09, "w": 0x0d, "x": 0x07,
    "y": 0x10, "z": 0x06,
    "0": 0x1d, "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15,
    "5": 0x17, "6": 0x16, "7": 0x1a, "8": 0x1c, "9": 0x19,
    "f1": 0x7a, "f2": 0x78, "f3": 0x63, "f4": 0x76, "f5": 0x60,
    "f6": 0x61, "f7": 0x62, "f8": 0x64, "f9": 0x65, "f10": 0x6d,
    "f11": 0x67, "f12": 0x6f,
    "arrowup": 0x7e, "arrowdown": 0x7d, "arrowleft": 0x7b, "arrowright": 0x7c,
    "up": 0x7e, "down": 0x7d, "left": 0x7b, "right": 0x7c,
    "home": 0x73, "end": 0x77, "pageup": 0x74, "pagedown": 0x79,
    "-": 0x1b, "=": 0x18, "[": 0x21, "]": 0x1e, "\\": 0x2a,
    ";": 0x29, "'": 0x27, "`": 0x32, ",": 0x2b, ".": 0x2f, "/": 0x2c,
]

func cgKey(chord: String) throws {
    let parts = chord.lowercased().split(separator: "+").map { String($0).trimmingCharacters(in: .whitespaces) }
    guard !parts.isEmpty else {
        throw ActionError.failed("Empty key chord.")
    }

    let modifierCodes: [CGKeyCode] = parts.dropLast().compactMap { keyMap[$0] }
    let mainKey = parts.last!
    guard let mainCode = keyMap[mainKey] else {
        throw ActionError.failed("Unknown key: \(mainKey)")
    }

    let source = CGEventSource(stateID: .hidSystemState)
    let keyDown = CGEvent(keyboardEventSource: source, virtualKey: mainCode, keyDown: true)
    guard let down = keyDown else {
        throw ActionError.failed("Failed to create key down event.")
    }
    let keyUp = CGEvent(keyboardEventSource: source, virtualKey: mainCode, keyDown: false)
    guard let up = keyUp else {
        throw ActionError.failed("Failed to create key up event.")
    }

    // Set modifier flags
    var flags: CGEventFlags = []
    for mod in modifierCodes {
        if mod == 0x37 { flags.insert(.maskCommand) }
        else if mod == 0x38 { flags.insert(.maskShift) }
        else if mod == 0x3a { flags.insert(.maskAlternate) }
        else if mod == 0x3b { flags.insert(.maskControl) }
        // Press modifier down
        let modDown = CGEvent(keyboardEventSource: source, virtualKey: mod, keyDown: true)
        modDown?.post(tap: .cghidEventTap)
    }

    down.flags = flags
    down.post(tap: .cghidEventTap)
    up.post(tap: .cghidEventTap)

    // Release modifiers in reverse order
    for mod in modifierCodes.reversed() {
        let modUp = CGEvent(keyboardEventSource: source, virtualKey: mod, keyDown: false)
        modUp?.post(tap: .cghidEventTap)
    }
}

// MARK: - CGEvent type (Unicode keyboard)

func cgType(_ text: String) throws {
    let source = CGEventSource(stateID: .hidSystemState)

    for char in text {
        if char == "\n" {
            // Type return for newline
            let down = CGEvent(keyboardEventSource: source, virtualKey: keyMap["return"]!, keyDown: true)
            let up = CGEvent(keyboardEventSource: source, virtualKey: keyMap["return"]!, keyDown: false)
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
            continue
        }

        // Use Unicode input via CGEvent
        let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
        guard let keyDownEvent = down else {
            throw ActionError.failed("Failed to create key down event for character.")
        }
        var chars = Array(String(char).utf16)
        keyDownEvent.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: &chars)
        keyDownEvent.post(tap: .cghidEventTap)

        let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        guard let keyUpEvent = up else {
            throw ActionError.failed("Failed to create key up event for character.")
        }
        keyUpEvent.post(tap: .cghidEventTap)
    }
}

// MARK: - CGEvent drag

func cgDrag(fromX: Double, fromY: Double, toX: Double, toY: Double, durationMs: Double) throws {
    let source = CGEventSource(stateID: .hidSystemState)
    let from = CGPoint(x: fromX, y: fromY)
    let to = CGPoint(x: toX, y: toY)

    // Mouse down at source
    let mouseDown = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: from, mouseButton: .left)
    guard let down = mouseDown else {
        throw ActionError.failed("Failed to create mouse down event for drag.")
    }
    down.post(tap: .cghidEventTap)

    // Interpolate over duration
    let steps = max(1, Int(durationMs / 16)) // ~60fps
    for i in 1...steps {
        let t = Double(i) / Double(steps)
        let x = fromX + (toX - fromX) * t
        let y = fromY + (toY - fromY) * t
        let point = CGPoint(x: x, y: y)
        let drag = CGEvent(mouseEventSource: source, mouseType: .leftMouseDragged, mouseCursorPosition: point, mouseButton: .left)
        guard let dragEvent = drag else {
            throw ActionError.failed("Failed to create mouse drag event.")
        }
        dragEvent.post(tap: .cghidEventTap)
        usleep(16000) // ~16ms per step
    }

    // Mouse up at destination
    let mouseUp = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: to, mouseButton: .left)
    guard let up = mouseUp else {
        throw ActionError.failed("Failed to create mouse up event for drag.")
    }
    up.post(tap: .cghidEventTap)
}
