import AppKit
import SwiftUI

@testable import Maloche

/// The accessibility tree of a view as VoiceOver gets it through the NSAccessibility protocol, read in-process from a
/// window that is never shown or key, and the problems found in it.
@MainActor
struct AccessibilityAudit {
    struct Element {
        var role = ""
        var label = ""
        var title = ""
        var value = ""
        var placeholder = ""
        var hasTitleElement = false
        var frame = CGRect.zero
        /// A cell or view of a SwiftUI control: SwiftUI's own accessibility modifiers on it are not visible in-process.
        var isSwiftUIPlatformElement = false
        /// The label set on the AppKit view of one of the app's representables, when its cell is the element.
        var viewLabel = ""
        var children: [Element] = []

        /// What VoiceOver announces as the element's name.
        var name: String {
            [label, title, placeholder].first { !$0.isEmpty } ?? (hasTitleElement ? "(title element)" : "")
        }

        var all: [Element] { [self] + children.flatMap(\.all) }
    }

    let root: Element
    /// Every problem as "role “name”: what is wrong".
    let problems: [String]

    static let interactiveRoles: Set<String> = [
        "AXButton", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuButton", "AXSlider", "AXIncrementor",
        "AXTextField", "AXTextArea", "AXComboBox", "AXDisclosureTriangle", "AXLink", "AXDateTimeArea", "AXColorWell",
    ]

    /// Hosts the view with SwiftUI's accessibility tree switched on and reads the tree.
    init(_ view: some View) {
        // the public switch for SwiftUI's accessibility nodes, without it the tree holds only AppKit controls
        let hosting = NSHostingView(rootView: view.environment(\.accessibilityEnabled, true))
        hosting.frame.size = hosting.fittingSize
        let window = Screenshots.Window()
        window.setContentSize(hosting.frame.size)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        // lets tasks such as the initial field focus run, the window stays off screen and never key
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        hosting.layoutSubtreeIfNeeded()
        root = Self.read(hosting)
        var problems: [String] = []
        Self.check(root, scope: "", problems: &problems)
        self.problems = problems
    }

    // MARK: Reading

    private static func object(_ element: Any, _ selector: String) -> Any? {
        guard let object = element as? NSObject, object.responds(to: Selector((selector))) else { return nil }
        return object.perform(Selector((selector)))?.takeUnretainedValue()
    }

    private static func text(_ element: Any, _ selector: String) -> String {
        switch object(element, selector) {
        case let string as String: string
        case let attributed as NSAttributedString: attributed.string
        case let number as NSNumber: number.stringValue
        default: ""
        }
    }

    private static func read(_ element: Any) -> Element {
        let node = element as AnyObject
        var result = Element()
        result.role = text(element, "accessibilityRole")
        result.label = text(element, "accessibilityLabel")
        result.title = text(element, "accessibilityTitle")
        let description = text(element, "accessibilityValueDescription")
        result.value = description.isEmpty ? text(element, "accessibilityValue") : description
        result.placeholder = text(element, "accessibilityPlaceholderValue")
        result.hasTitleElement = object(element, "accessibilityTitleUIElement") != nil
        result.frame = node.accessibilityFrame?() ?? .zero
        if let view = (element as? NSCell)?.controlView ?? (element as? NSView) {
            let host = sequence(first: view, next: \.superview).map { String(reflecting: type(of: $0)) }
                .first { $0.hasPrefix("SwiftUI.AppKitPlatformViewHost") }
            result.isSwiftUIPlatformElement = host.map { !$0.contains("Maloche.") } ?? false
            if element is NSCell, host?.contains("Maloche.") == true {
                result.viewLabel = view.accessibilityLabel() ?? ""
            }
        }
        let children = (object(element, "accessibilityChildren") as? [Any]) ?? []
        for child in children {
            let child = child as AnyObject
            guard child.isAccessibilityHidden?() != true else { continue }
            let read = read(child)
            // an ignored element such as a control view hands its children to its parent
            if child.isAccessibilityElement?() == false {
                result.children += read.children
            } else {
                result.children.append(read)
            }
        }
        return result
    }

    // MARK: Problems

    /// `scope` is the label of the nearest labelled group, names of controls must differ within it.
    private static func check(_ element: Element, scope: String?, problems: inout [String]) {
        if let scope {
            var names: [String: Int] = [:]
            func count(_ element: Element) {
                for child in element.children {
                    if interactiveRoles.contains(child.role), !child.name.isEmpty { names[child.name, default: 0] += 1 }
                    if child.label.isEmpty { count(child) }
                }
            }
            count(element)
            for (name, times) in names where times > 1 {
                problems.append("“\(name)” \(times) times in “\(scope)”: ambiguous")
            }
        }
        for (index, child) in element.children.enumerated() {
            problems += Self.problems(of: child)
            if index > 0 { problems += order(element.children[index - 1], child) }
            check(child, scope: child.label.isEmpty ? nil : child.label, problems: &problems)
        }
    }

    private static func describe(_ element: Element) -> String {
        "\(element.role) “\(element.name.isEmpty ? element.value : element.name)”"
    }

    private static func problems(of element: Element) -> [String] {
        var problems: [String] = []
        let name = element.name
        // SwiftUI's label of its own text fields, date pickers and switches does not show in-process
        if interactiveRoles.contains(element.role), name.isEmpty, !element.isSwiftUIPlatformElement {
            problems.append("\(describe(element)): no name")
        }
        if element.role == "AXImage", element.label.isEmpty {
            problems.append("\(describe(element)): image without description")
        }
        if element.role == "AXUnknown" {
            problems.append("\(describe(element)): no role, VoiceOver may skip it")
        }
        if element.role == "AXStaticText", name.isEmpty, element.value.isEmpty {
            problems.append("\(describe(element)): empty text")
        }
        if !element.viewLabel.isEmpty, element.label != element.viewLabel {
            problems.append("\(describe(element)): label “\(element.viewLabel)” is set on the view, not the cell")
        }
        for text in [element.label, element.title, element.value, element.placeholder] where meaningless(text) {
            problems.append("\(describe(element)): meaningless name “\(text)”")
        }
        let editable: Set<String> = ["AXTextField", "AXComboBox", "AXDateTimeArea", "AXSlider"]
        for text in [element.label, element.title] + (editable.contains(element.role) ? [] : [element.value])
        where readsDurationAsClock(text) {
            problems.append("\(describe(element)): duration read as a clock time in “\(text)”")
        }
        return problems
    }

    /// The next sibling is read after an element it sits above in the same column, or left of on the same line.
    private static func order(_ previous: Element, _ next: Element) -> [String] {
        let a = previous.frame
        let b = next.frame
        guard a.width > 0, a.height > 0, b.width > 0, b.height > 0 else { return [] }
        let sameColumn = b.minX < a.maxX && a.minX < b.maxX
        let sameLine = min(a.maxY, b.maxY) - max(a.minY, b.minY) > min(a.height, b.height) / 2
        if (sameColumn && b.minY >= a.maxY + 2) || (sameLine && b.maxX <= a.minX - 2) {
            return ["\(describe(next)) is read after \(describe(previous)) but comes first on screen"]
        }
        return []
    }

    /// SF Symbol names, format specifiers and names without a letter or digit.
    static func meaningless(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        if text.wholeMatch(of: /[a-z0-9]+(\.[a-z0-9]+)+/) != nil { return true }
        if text.contains(/%(@|l*d|f)/) { return true }
        return !text.contains(where: { $0.isLetter || $0.isNumber })
    }

    /// An "h:mm" that is neither a time after "Since", "from", "to" or "at" nor the start of a "… to …" span.
    static func readsDurationAsClock(_ text: String) -> Bool {
        text.matches(of: /\d{1,3}:\d{2}/).contains { match in
            let before = text[..<match.range.lowerBound]
            let after = text[match.range.upperBound...]
            let isTime =
                before.contains(/(?i)(since|from|to|until|at)\s*$/)
                || after.prefixMatch(of: /\s*([AaPp]\.?\s?[Mm]\.?)?\s+to\b/) != nil
            return !isTime
        }
    }
}
