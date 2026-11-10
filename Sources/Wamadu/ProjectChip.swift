import AppKit
import SwiftUI
import WamaduCore

/// The project of a new activity; a click or a changed `menuRequest` opens the project menu.
struct ProjectChip: View {
    let catalog: Catalog
    @Binding var projectId: Int64?
    @Binding var menuRequest: Int
    let onNewProject: () -> Void

    var body: some View {
        let project = catalog.project(projectId)
        let name = project?.name ?? String(localized: "No project")
        Button {
            menuRequest += 1
        } label: {
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        Color(
                            nsColor: project.map { CustomerColor.nsColor(for: catalog.customer($0.customerId)) }
                                ?? .tertiaryLabelColor)
                    )
                    .frame(width: 8, height: 8)
                Text(name).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").imageScale(.small)
            }
        }
        .controlSize(.small)
        .fixedSize()
        .background(
            ProjectMenu(catalog: catalog, projectId: $projectId, request: menuRequest, onNewProject: onNewProject)
        )
        .accessibilityLabel(String(localized: "Project"))
        .accessibilityValue(name)
    }
}

/// Pops up the project menu below its view whenever `request` changes.
private struct ProjectMenu: NSViewRepresentable {
    let catalog: Catalog
    @Binding var projectId: Int64?
    let request: Int
    let onNewProject: () -> Void

    private static let noProject = 0
    private static let newProject = -1

    func makeCoordinator() -> Coordinator { Coordinator(request: request) }

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        guard request != coordinator.request else { return }
        coordinator.request = request
        coordinator.menu = makeMenu(target: coordinator)
        coordinator.anchor = view
        // a run loop perform, menu tracking inside a main queue block would stall every other main queue job
        coordinator.perform(#selector(Coordinator.popUp), with: nil, afterDelay: 0)
    }

    private func makeMenu(target: Coordinator) -> NSMenu {
        let menu = NSMenu()
        let selected = projectId.map { Int($0) } ?? Self.noProject
        func add(_ title: String, tag: Int, color: NSColor?) {
            let item = menu.addItem(withTitle: title, action: #selector(Coordinator.picked(_:)), keyEquivalent: "")
            item.target = target
            item.tag = tag
            item.state = tag == selected ? .on : .off
            item.image = color.flatMap(NSImage.swatch)
        }
        add(String(localized: "No project"), tag: Self.noProject, color: .tertiaryLabelColor)
        let byCustomer = Dictionary(grouping: catalog.projects, by: \.customerId)
        for project in byCustomer[nil] ?? [] {
            add(project.name, tag: Int(project.id ?? 0), color: .systemGray)
        }
        for customer in catalog.customers {
            guard let projects = byCustomer[customer.id] else { continue }
            menu.addItem(.sectionHeader(title: customer.name))
            for project in projects {
                add(project.name, tag: Int(project.id ?? 0), color: CustomerColor.nsColor(for: customer))
            }
        }
        menu.addItem(.separator())
        add(String(localized: "New project…"), tag: Self.newProject, color: nil)
        return menu
    }

    @MainActor final class Coordinator: NSObject {
        var parent: ProjectMenu?
        var request: Int
        var menu: NSMenu?
        weak var anchor: NSView?

        init(request: Int) { self.request = request }

        @objc func popUp() {
            guard let menu, let anchor, anchor.window?.isVisible == true else { return }
            self.menu = nil
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: anchor)
        }

        @objc func picked(_ item: NSMenuItem) {
            switch item.tag {
            case ProjectMenu.newProject: parent?.onNewProject()
            case ProjectMenu.noProject: parent?.projectId = nil
            default: parent?.projectId = Int64(item.tag)
            }
        }
    }
}

extension NSImage {
    /// The customer color square of a menu item.
    static func swatch(_ color: NSColor) -> NSImage? {
        NSImage(systemSymbolName: "square.fill", accessibilityDescription: nil)?.withSymbolConfiguration(
            .init(pointSize: 9, weight: .regular).applying(.init(paletteColors: [color])))
    }
}
