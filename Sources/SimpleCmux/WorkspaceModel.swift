import Foundation
import SwiftUI

final class TerminalTab: Identifiable, ObservableObject {
    let id = UUID()
    let title: String

    init(number: Int) {
        title = String(localized: "terminal.title", defaultValue: "Terminal \(number)")
    }
}

final class Workspace: Identifiable, ObservableObject {
    let id = UUID()
    let name: String
    @Published var tabs: [TerminalTab]
    @Published var selectedTabID: TerminalTab.ID

    init(name: String) {
        self.name = name
        let firstTab = TerminalTab(number: 1)
        tabs = [firstTab]
        selectedTabID = firstTab.id
    }

    @discardableResult
    func addTab() -> TerminalTab {
        let tab = TerminalTab(number: tabs.count + 1)
        tabs.append(tab)
        selectedTabID = tab.id
        return tab
    }

    func closeTab(_ tab: TerminalTab) {
        guard tabs.count > 1, let index = tabs.firstIndex(where: { $0.id == tab.id }) else {
            return
        }

        tabs.remove(at: index)
        if selectedTabID == tab.id {
            selectedTabID = tabs[min(index, tabs.count - 1)].id
        }
    }
}

@MainActor
final class WorkspaceStore: ObservableObject {
    @Published private(set) var workspaces: [Workspace]
    @Published var selectedWorkspaceID: Workspace.ID

    init() {
        let initialWorkspaces = [
            Workspace(name: String(localized: "workspace.main", defaultValue: "Main")),
            Workspace(name: String(localized: "workspace.development", defaultValue: "Development")),
            Workspace(name: String(localized: "workspace.scratch", defaultValue: "Scratch"))
        ]
        workspaces = initialWorkspaces
        selectedWorkspaceID = initialWorkspaces[0].id
    }

    var selectedWorkspace: Workspace {
        workspaces.first { $0.id == selectedWorkspaceID } ?? workspaces[0]
    }

    func selectWorkspace(_ workspace: Workspace) {
        selectedWorkspaceID = workspace.id
    }

    func addWorkspace() {
        let number = workspaces.count + 1
        let workspace = Workspace(
            name: String(localized: "workspace.numbered", defaultValue: "Workspace \(number)")
        )
        workspaces.append(workspace)
        selectedWorkspaceID = workspace.id
    }

    func addTab() {
        selectedWorkspace.addTab()
    }
}
