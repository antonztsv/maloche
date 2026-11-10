import AppKit
import SwiftUI
import WamaduCore

/// Shown at the first launch; Start or closing it marks the welcome done.
@MainActor
final class WelcomeWindowController: NSObject, NSWindowDelegate {
    static let width: CGFloat = 560

    private let model: AppModel
    private let isLoginItem: () -> Bool
    private let setLoginItem: (Bool) throws -> Void
    private(set) lazy var window = makeWindow()

    init(
        model: AppModel, isLoginItem: @escaping () -> Bool = { LoginItem.isEnabled },
        setLoginItem: @escaping (Bool) throws -> Void = { try LoginItem.setEnabled($0) }
    ) {
        self.model = model
        self.isLoginItem = isLoginItem
        self.setLoginItem = setLoginItem
    }

    /// At launch only; a normal window needs the app active.
    func show() {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func start(_ welcome: Welcome, openAtLogin: Bool) {
        if openAtLogin != isLoginItem() {
            do {
                try setLoginItem(openAtLogin)
            } catch {
                appLog.error("changing the login item failed: \(String(describing: error), privacy: .public)")
            }
        }
        model.finishWelcome(welcome)
        window.close()
    }

    func windowWillClose(_ notification: Notification) {
        model.finishWelcome(nil)
    }

    private func makeWindow() -> NSWindow {
        let view = WelcomeView(model: model, openAtLogin: true) { [weak self] in self?.start($0, openAtLogin: $1) }
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = String(localized: "Welcome to wamadu")
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }
}

/// The principle, work days and hours, check-in interval and login item; Start applies them.
struct WelcomeView: View {
    let model: AppModel
    let onStart: (Welcome, Bool) -> Void
    @State private var welcome: Welcome
    @State private var openAtLogin: Bool
    @State private var importFlow = DailyImportFlow()
    @Environment(\.dismiss) private var dismiss

    private var calendar: Calendar { model.calendar }

    init(model: AppModel, openAtLogin: Bool, onStart: @escaping (Welcome, Bool) -> Void) {
        self.model = model
        _welcome = State(initialValue: Welcome(settings: model.settings, calendar: model.calendar))
        _openAtLogin = State(initialValue: openAtLogin)
        self.onStart = onStart
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .accessibilityHidden(true)
                Text("Welcome to wamadu")
                    .font(.title.bold())
                Text("Every now and then, wamadu asks what you are working on. One answer, and your day fills itself.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 32)
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("When do you work?")
                        HStack(spacing: 6) {
                            ForEach(calendar.orderedWeekdays, id: \.self, content: day)
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel(Text("Work days"))
                        HStack(spacing: 8) {
                            Text("From")
                                .foregroundStyle(.secondary)
                            PlanFields(
                                plan: $welcome.plan, startLabel: String(localized: "Start of work day"),
                                endLabel: String(localized: "End of work day"), calendar: calendar)
                        }
                        .datePickerStyle(.field)
                        .labelsHidden()
                    }
                    Picker("Check in every", selection: $welcome.checkInInterval) {
                        GeneralSettingsView.durations(including: welcome.checkInInterval)
                    }
                    Toggle("Open at login", isOn: $openAtLogin)
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Text("Coming from Daily?")
                                .foregroundStyle(.secondary)
                            Button("Import your data") { importFlow.choose(model: model) }
                                .buttonStyle(.link)
                        }
                        Text("You can change all of this later in Settings.")
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Start") { onStart(welcome, openAtLogin) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(welcome.days.isEmpty)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: WelcomeWindowController.width)
        // the header sits under the transparent title bar
        .ignoresSafeArea(edges: .top)
        .dailyImport(importFlow, model: model)
        .keyCommand(.escape, modifiers: []) { dismiss() }
    }

    private func day(_ weekday: Int) -> some View {
        Toggle(
            calendar.shortStandaloneWeekdaySymbols[weekday - 1],
            isOn: Binding {
                welcome.days.contains(weekday)
            } set: { on in
                if on { welcome.days.insert(weekday) } else { welcome.days.remove(weekday) }
            }
        )
        .toggleStyle(.button)
        .buttonBorderShape(.capsule)
        .accessibilityLabel(calendar.standaloneWeekdaySymbols[weekday - 1])
    }
}
