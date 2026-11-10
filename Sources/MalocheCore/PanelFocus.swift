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
        case (.statusItem, true): key ? .close : .focus
        case (.shortcut, true): .focus
        }
    }

    public enum Outcome: Equatable, Sendable { case keep, closeEditor, closeAll }

    /// Where the key status went after the dashboard or the entry editor gave it up: the editor closes like a
    /// transient popover, both close when the key status left the app's panels.
    public static func afterResignKey<Window: Equatable>(key: Window?, dashboard: Window, editor: Window) -> Outcome {
        switch key {
        case editor?: .keep
        case dashboard?: .closeEditor
        default: .closeAll
        }
    }
}
