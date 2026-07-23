import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

struct TreeNode: Encodable {
    let id: String
    let role: String
    let subrole: String?
    let label: String?
    let description: String?
    let value: AnyCodableValue?
    let enabled: Bool
    let focused: Bool
    let secure: Bool
    let frame: LogicalFrame?
    let actions: [String]
    let children: [TreeNode]

    enum CodingKeys: String, CodingKey {
        case id, role, subrole, label, description, value, enabled, focused, secure, frame, actions, children
    }
}

enum AnyCodableValue: Encodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(v): try container.encode(v)
        case let .number(v): try container.encode(v)
        case let .bool(v): try container.encode(v)
        case .null: try container.encodeNil()
        }
    }
}

final class ElementCache {
    private var elements: [String: AXUIElement] = [:]
    private var counter: Int = 0
    private var cachedRevision: UInt64 = 0

    func beginRevision(_ rev: UInt64) {
        elements.removeAll()
        counter = 0
        cachedRevision = rev
    }

    func register(_ element: AXUIElement) -> String {
        let id = "e\(counter)"
        counter += 1
        elements[id] = element
        return id
    }

    func resolve(_ id: String, revision: UInt64) -> AXUIElement? {
        guard revision == cachedRevision else { return nil }
        return elements[id]
    }

    var currentRevision: UInt64 { cachedRevision }
}

enum TreeQueryError: Error {
    case permissionDenied
    case targetNotFound
    case ambiguousTarget
    case timedOut
    case failed(String)
}

struct TreeTraversalConfig {
    let maxDepth: Int
    let maxNodes: Int
    let visibleOnly: Bool
    let condenseContainers: Bool
}

struct TreeTraversalResult {
    let root: TreeNode
    let truncated: Bool
    let nodeCount: Int
}

func queryTree(
    appRef: AXUIElement,
    windowRef: AXUIElement?,
    config: TreeTraversalConfig,
    cache: ElementCache,
    deadline: UInt64
) throws -> TreeTraversalResult {
    let rootElement = windowRef ?? appRef
    var visited = Set<AXElementIdentity>()
    var nodeCount = 0
    var truncated = false

    let root = try buildNode(
        from: rootElement,
        depth: 0,
        config: config,
        cache: cache,
        deadline: deadline,
        visited: &visited,
        nodeCount: &nodeCount,
        truncated: &truncated
    )

    if let root = root {
        return TreeTraversalResult(root: root, truncated: truncated, nodeCount: nodeCount)
    } else {
        throw TreeQueryError.failed("Unable to build tree root.")
    }
}

func buildNode(
    from element: AXUIElement,
    depth: Int,
    config: TreeTraversalConfig,
    cache: ElementCache,
    deadline: UInt64,
    visited: inout Set<AXElementIdentity>,
    nodeCount: inout Int,
    truncated: inout Bool
) throws -> TreeNode? {
    guard DispatchTime.now().uptimeNanoseconds < deadline else {
        truncated = true
        return nil
    }
    guard nodeCount < config.maxNodes else {
        truncated = true
        return nil
    }

    let identity = AXElementIdentity(element: element)
    guard visited.insert(identity).inserted else {
        return nil
    }
    nodeCount += 1

    let role = axString(element, kAXRoleAttribute) ?? "unknown"
    let subrole = axString(element, kAXSubroleAttribute)
    let label = axString(element, kAXDescriptionAttribute)
    let helpText = axString(element, kAXHelpAttribute)

    let enabled = axBool(element, kAXEnabledAttribute) ?? false
    let focused = axBool(element, kAXFocusedAttribute) ?? false

    let isSecure = (axBool(element, "AXIsSecure") ?? false)
        || (axString(element, kAXSubroleAttribute)?.contains("Secure") ?? false)
        || role.contains("Secure")
    let value: AnyCodableValue?
    if isSecure {
        value = .null
    } else {
        value = axValue(element, kAXValueAttribute)
    }

    let frame = try? axFrameFromElement(element)
    let actions = axActionNames(element)

    if config.visibleOnly {
        let isVisible = axBool(element, "AXVisible") ?? true
        if !isVisible && depth > 0 {
            return nil
        }
    }

    let id = cache.register(element)

    var children: [TreeNode] = []
    if depth < config.maxDepth {
        if let childElements = axChildren(element) {
            for child in childElements {
                guard DispatchTime.now().uptimeNanoseconds < deadline else {
                    truncated = true
                    break
                }
                guard nodeCount < config.maxNodes else {
                    truncated = true
                    break
                }
                if let childNode = try buildNode(
                    from: child,
                    depth: depth + 1,
                    config: config,
                    cache: cache,
                    deadline: deadline,
                    visited: &visited,
                    nodeCount: &nodeCount,
                    truncated: &truncated
                ) {
                    children.append(childNode)
                }
            }
        }
    } else if axChildren(element) != nil {
        truncated = true
    }

    return TreeNode(
        id: id,
        role: role,
        subrole: subrole,
        label: label,
        description: helpText,
        value: value,
        enabled: enabled,
        focused: focused,
        secure: isSecure,
        frame: frame,
        actions: actions,
        children: children
    )
}

// MARK: - AX helpers

func axString(_ element: AXUIElement, _ attribute: String) -> String? {
    var raw: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &raw)
    guard error == .success, let value = raw as? String else { return nil }
    return value
}

func axBool(_ element: AXUIElement, _ attribute: String) -> Bool? {
    var raw: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &raw)
    guard error == .success else { return nil }
    if let value = raw as? Bool { return value }
    if let value = raw as? Int { return value != 0 }
    if let value = raw as? NSNumber { return value.boolValue }
    return nil
}

func axValue(_ element: AXUIElement, _ attribute: String) -> AnyCodableValue {
    var raw: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &raw)
    guard error == .success, let value = raw else { return .null }

    if let s = value as? String { return .string(s) }
    if let n = value as? NSNumber {
        if CFGetTypeID(n) == CFBooleanGetTypeID() {
            return .bool(n.boolValue)
        }
        return .number(n.doubleValue)
    }
    if let b = value as? Bool { return .bool(b) }
    if let i = value as? Int { return .number(Double(i)) }
    if let d = value as? Double { return .number(d) }
    return .null
}

func axChildren(_ element: AXUIElement) -> [AXUIElement]? {
    var raw: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &raw)
    guard error == .success, let array = raw as? [AXUIElement] else { return nil }
    return array
}

func axActionNames(_ element: AXUIElement) -> [String] {
    var names: CFArray?
    let error = AXUIElementCopyActionNames(element, &names)
    guard error == .success, let array = names as? [String] else { return [] }
    return array
}

func axFrameFromElement(_ element: AXUIElement) throws -> LogicalFrame {
    var positionRaw: CFTypeRef?
    let posError = AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRaw)
    guard posError == .success, let positionValue = positionRaw else {
        throw TreeQueryError.failed("Unable to get AX position.")
    }
    let positionAXValue = positionValue as! AXValue
    var point = CGPoint.zero
    guard AXValueGetValue(positionAXValue, .cgPoint, &point) else {
        throw TreeQueryError.failed("Unable to extract AX position.")
    }

    var sizeRaw: CFTypeRef?
    let sizeError = AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRaw)
    guard sizeError == .success, let sizeValue = sizeRaw else {
        throw TreeQueryError.failed("Unable to get AX size.")
    }
    let sizeAXValue = sizeValue as! AXValue
    var size = CGSize.zero
    guard AXValueGetValue(sizeAXValue, .cgSize, &size) else {
        throw TreeQueryError.failed("Unable to extract AX size.")
    }

    return LogicalFrame(x: Double(point.x), y: Double(point.y), width: Double(size.width), height: Double(size.height))
}

// MARK: - Cycle detection

struct AXElementIdentity: Hashable {
    let element: AXUIElement

    static func == (lhs: AXElementIdentity, rhs: AXElementIdentity) -> Bool {
        CFEqual(lhs.element, rhs.element)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(CFHash(element))
    }
}

// MARK: - Find

struct FindCondition {
    let role: String?
    let label: String?
    let labelContains: String?
    let value: String?
    let enabled: Bool?
    let focused: Bool?
}

func findInTree(
    appRef: AXUIElement,
    windowRef: AXUIElement?,
    condition: FindCondition,
    config: TreeTraversalConfig,
    cache: ElementCache,
    deadline: UInt64
) throws -> (results: [TreeNode], truncated: Bool, nodeCount: Int) {
    let rootElement = windowRef ?? appRef
    var visited = Set<AXElementIdentity>()
    var nodeCount = 0
    var truncated = false
    var results: [TreeNode] = []

    findInNode(
        from: rootElement,
        depth: 0,
        condition: condition,
        config: config,
        cache: cache,
        deadline: deadline,
        visited: &visited,
        nodeCount: &nodeCount,
        truncated: &truncated,
        results: &results
    )

    return (results, truncated, nodeCount)
}

func findInNode(
    from element: AXUIElement,
    depth: Int,
    condition: FindCondition,
    config: TreeTraversalConfig,
    cache: ElementCache,
    deadline: UInt64,
    visited: inout Set<AXElementIdentity>,
    nodeCount: inout Int,
    truncated: inout Bool,
    results: inout [TreeNode]
) {
    guard DispatchTime.now().uptimeNanoseconds < deadline else {
        truncated = true
        return
    }
    guard nodeCount < config.maxNodes else {
        truncated = true
        return
    }

    let identity = AXElementIdentity(element: element)
    guard visited.insert(identity).inserted else { return }
    nodeCount += 1

    let role = axString(element, kAXRoleAttribute) ?? "unknown"
    let isSecure = (axBool(element, "AXIsSecure") ?? false)
        || (axString(element, kAXSubroleAttribute)?.contains("Secure") ?? false)
        || role.contains("Secure")
    let label = axString(element, kAXDescriptionAttribute)

    if matchesCondition(role: role, label: label, isSecure: isSecure, element: element, condition: condition) {
        let subrole = axString(element, kAXSubroleAttribute)
        let helpText = axString(element, kAXHelpAttribute)
        let enabled = axBool(element, kAXEnabledAttribute) ?? false
        let focused = axBool(element, kAXFocusedAttribute) ?? false
        let value: AnyCodableValue?
        if isSecure {
            value = .null
        } else {
            value = axValue(element, kAXValueAttribute)
        }
        let frame = try? axFrameFromElement(element)
        let actions = axActionNames(element)
        let id = cache.register(element)

        results.append(TreeNode(
            id: id,
            role: role,
            subrole: subrole,
            label: label,
            description: helpText,
            value: value,
            enabled: enabled,
            focused: focused,
            secure: isSecure,
            frame: frame,
            actions: actions,
            children: []
        ))
    }

    if depth < config.maxDepth {
        if let childElements = axChildren(element) {
            for child in childElements {
                guard DispatchTime.now().uptimeNanoseconds < deadline else {
                    truncated = true
                    break
                }
                guard nodeCount < config.maxNodes else {
                    truncated = true
                    break
                }
                findInNode(
                    from: child,
                    depth: depth + 1,
                    condition: condition,
                    config: config,
                    cache: cache,
                    deadline: deadline,
                    visited: &visited,
                    nodeCount: &nodeCount,
                    truncated: &truncated,
                    results: &results
                )
            }
        }
    }
}

func matchesCondition(role: String, label: String?, isSecure: Bool, element: AXUIElement, condition: FindCondition) -> Bool {
    if let conditionRole = condition.role, role != conditionRole {
        return false
    }
    if let conditionLabel = condition.label {
        if label != conditionLabel {
            return false
        }
    }
    if let conditionLabelContains = condition.labelContains {
        if label == nil || !(label!.contains(conditionLabelContains)) {
            return false
        }
    }
    if let conditionValue = condition.value {
        if isSecure { return false }
        let actualValue = axValue(element, kAXValueAttribute)
        guard case let .string(actualString) = actualValue, actualString == conditionValue else {
            return false
        }
    }
    if let conditionEnabled = condition.enabled {
        let actualEnabled = axBool(element, kAXEnabledAttribute) ?? false
        if actualEnabled != conditionEnabled {
            return false
        }
    }
    if let conditionFocused = condition.focused {
        let actualFocused = axBool(element, kAXFocusedAttribute) ?? false
        if actualFocused != conditionFocused {
            return false
        }
    }
    return true
}


struct TreeTargetFingerprint: Encodable {
    let appPid: Int32
    let windowTitle: String?
}

func axPid(_ element: AXUIElement) -> Int32 {
    var pid: pid_t = 0
    AXUIElementGetPid(element, &pid)
    return pid
}
