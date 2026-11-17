import AppKit
import MalocheCore
import SwiftUI

/// The project of a new activity, or its customer without project; a click or a changed `menuRequest` opens the menu.
struct ProjectChip: View {
    let catalog: Catalog
    @Binding var projectId: Int64?
    @Binding var customerId: Int64?
    @Binding var menuRequest: Int
    let onNew: (ProjectDraft) -> Void

    var body: some View {
        let project = catalog.project(projectId)
        let customer = catalog.customer(project?.customerId ?? customerId)
        let name = project?.name ?? customer?.name ?? String(localized: "No project")
        Button {
            menuRequest += 1
        } label: {
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(nsColor: customer.map { CustomerColor.nsColor(for: $0) } ?? .tertiaryLabelColor))
                    .frame(width: 8, height: 8)
                Text(name).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").imageScale(.small)
            }
        }
        .controlSize(.small)
        .fixedSize()
        .background(
            ProjectMenu(
                catalog: catalog, projectId: $projectId, customerId: $customerId, request: menuRequest, onNew: onNew)
        )
        .accessibilityLabel(String(localized: "Project"))
        .accessibilityValue(name)
    }
}

/// Pops up the project menu below its view whenever `request` changes.
private struct ProjectMenu: NSViewRepresentable {
    let catalog: Catalog
    @Binding var projectId: Int64?
    @Binding var customerId: Int64?
    let request: Int
    let onNew: (ProjectDraft) -> Void

    enum Pick: Equatable {
        case placement(projectId: Int64?, customerId: Int64?)
        case newProject, newCustomer
    }

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

    /// Projects without customer under No project, then per customer No project, which picks the customer, and its
    /// projects.
    private func makeMenu(target: Coordinator) -> NSMenu {
        let menu = NSMenu()
        let selected = Pick.placement(projectId: projectId, customerId: customerId)
        func add(_ title: String, _ pick: Pick, color: NSColor?) {
            let item = menu.addItem(withTitle: title, action: #selector(Coordinator.picked(_:)), keyEquivalent: "")
            item.target = target
            item.representedObject = pick
            item.state = pick == selected ? .on : .off
            item.image = color.flatMap(NSImage.swatch)
        }
        for (customer, projects) in catalog.projectMenu {
            let color = customer.map { CustomerColor.nsColor(for: $0) }
            if let customer { menu.addItem(.sectionHeader(title: customer.name)) }
            add(
                String(localized: "No project"), .placement(projectId: nil, customerId: customer?.id),
                color: color ?? .tertiaryLabelColor)
            for project in projects {
                add(project.name, .placement(projectId: project.id, customerId: nil), color: color ?? .systemGray)
            }
        }
        menu.addItem(.separator())
        add(String(localized: "New project…"), .newProject, color: nil)
        add(String(localized: "New customer…"), .newCustomer, color: nil)
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
            switch item.representedObject as? Pick {
            case .newProject: parent?.onNew(ProjectDraft())
            case .newCustomer: parent?.onNew(ProjectDraft(forCustomer: true))
            case .placement(let projectId, let customerId):
                parent?.projectId = projectId
                parent?.customerId = customerId
            case nil: break
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
