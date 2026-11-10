import AppKit
import MalocheCore

extension CustomerColor {
    var nsColor: NSColor {
        switch self {
        case .blue: .systemBlue
        case .purple: .systemPurple
        case .orange: .systemOrange
        case .teal: .systemTeal
        case .pink: .systemPink
        case .green: .systemGreen
        case .indigo: .systemIndigo
        case .brown: .systemBrown
        }
    }

    var name: String {
        switch self {
        case .blue: String(localized: "Blue")
        case .purple: String(localized: "Purple")
        case .orange: String(localized: "Orange")
        case .teal: String(localized: "Teal")
        case .pink: String(localized: "Pink")
        case .green: String(localized: "Green")
        case .indigo: String(localized: "Indigo")
        case .brown: String(localized: "Brown")
        }
    }

    /// Without a customer gray.
    static func nsColor(for customer: Customer?) -> NSColor {
        customer.flatMap { CustomerColor(rawValue: $0.colorIndex) }?.nsColor ?? .systemGray
    }
}
