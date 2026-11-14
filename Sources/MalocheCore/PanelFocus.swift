/// Decides how the panel reacts to the ways it can be opened; the app never steals focus on its own.
public enum PanelFocus {
    public enum Trigger: Sendable {
        case timer, statusItem, shortcut
    }

    public enum Action: Equatable, Sendable {
        case show(focus: Bool)
        /// Refresh the visible panel without changing focus.
        case update
        case focus
        case close
    }

    public static func action(for trigger: Trigger, visible: Bool, key: Bool) -> Action {
        switch (trigger, visible) {
        case (.timer, false): .show(focus: false)
        case (.timer, true): .update
        case (_, false): .show(focus: true)
        case (.statusItem, true): .close
        case (.shortcut, true): .focus
        }
    }
}
