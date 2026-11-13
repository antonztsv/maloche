#if DEBUG
    import AppKit
    import Observation

    /// Manual testing: `open "maloche Dev.app" --args -DebugHighlightVariant cycle`.
    @MainActor
    @Observable
    final class HighlightDiagnosis {
        static let shared = HighlightDiagnosis()
        static var isActive: Bool { UserDefaults.standard.string(forKey: "DebugHighlightVariant") == "cycle" }

        private(set) var caption: String?
        @ObservationIgnored private var button: NSButton?
        @ObservationIgnored private var highlight: StatusItemHighlight?
        @ObservationIgnored private var cycle: Timer?
        @ObservationIgnored private var delayed: Timer?
        @ObservationIgnored private var index = 0

        private let variants: [(letter: String, name: String)] = [
            ("A", "re-apply after every event"), ("B", "push on push off toggle"),
            ("C", "left mouse down action"), ("D", "isHighlighted after 0.3 s timer"),
            ("E", "cell isHighlighted"),
        ]

        func attach(item: NSStatusItem, highlight: StatusItemHighlight?) {
            button = item.button
            self.highlight = highlight
            item.button?.sendAction(on: [.leftMouseDown])
        }

        func panelVisibilityChanged(_ visible: Bool) {
            if visible, cycle == nil {
                index = 0
                runVariant()
                let timer = Timer(timeInterval: 4, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.next() }
                }
                RunLoop.main.add(timer, forMode: .common)
                cycle = timer
            } else if !visible, cycle != nil {
                cycle?.invalidate()
                cycle = nil
                reset()
                caption = nil
            }
        }

        private func next() {
            index = (index + 1) % variants.count
            runVariant()
        }

        private func reset() {
            delayed?.invalidate()
            highlight?.enabled = false
            guard let button else { return }
            button.highlight(false)
            button.isHighlighted = false
            button.cell?.isHighlighted = false
            button.setButtonType(.momentaryPushIn)
            button.state = .off
        }

        private func runVariant() {
            reset()
            let variant = variants[index]
            caption = "\(variant.letter): \(variant.name)"
            appLog.notice("highlight variant \(variant.letter, privacy: .public) \(variant.name, privacy: .public)")
            guard let button else { return }
            switch variant.letter {
            case "A":
                highlight?.enabled = true
                highlight?.apply()
            case "B":
                button.setButtonType(.pushOnPushOff)
                button.state = .on
            case "C":
                button.highlight(true)
            case "D":
                delayed = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak button] _ in
                    MainActor.assumeIsolated { button?.isHighlighted = true }
                }
            default:
                button.cell?.isHighlighted = true
            }
        }
    }
#endif
