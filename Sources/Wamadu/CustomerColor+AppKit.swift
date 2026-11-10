import AppKit
import WamaduCore

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

    /// Without a customer gray.
    static func nsColor(for customer: Customer?) -> NSColor {
        customer.flatMap { CustomerColor(rawValue: $0.colorIndex) }?.nsColor ?? .systemGray
    }
}
