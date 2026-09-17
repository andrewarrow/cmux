import Combine
import Foundation
import SwiftUI

final class TerminalTab: Identifiable, ObservableObject {
    let id: UUID
    let title: String
    @Published private(set) var currentDirectory: String?
    var currentDirectoryProvider: (() -> String?)?

    init(
        id: UUID = UUID(),
        title: String? = nil,
        number: Int,
        currentDirectory: String? = nil
    ) {
        self.id = id
        self.title = title
            ?? String(localized: "terminal.title", defaultValue: "Terminal \(number)")
        self.currentDirectory = currentDirectory
    }

    func workingDirectoryForNewTab() -> String? {
        currentDirectoryProvider?() ?? currentDirectory
    }

    func refreshCurrentDirectory() {
        updateCurrentDirectory(workingDirectoryForNewTab())
    }

    func updateCurrentDirectory(_ directory: String?) {
        guard currentDirectory != directory else { return }
        currentDirectory = directory
    }
}

final class Workspace: Identifiable, ObservableObject {
    let id: UUID
    private let fallbackName: String
    @Published private(set) var tabs: [TerminalTab]
    @Published private(set) var selectedTabID: TerminalTab.ID

    var didChange: (() -> Void)?
    private var firstTabDirectoryObservation: AnyCancellable?

    var name: String {
        tabs.first?.currentDirectory ?? fallbackName
    }

    init(name: String) {
        id = UUID()
        fallbackName = name
        let firstTab = TerminalTab(number: 1)
        tabs = [firstTab]
        selectedTabID = firstTab.id
        observeFirstTabDirectory()
    }

    fileprivate init(
        id: UUID,
        name: String,
        tabs: [TerminalTab],
        selectedTabID: TerminalTab.ID
    ) {
        self.id = id
        fallbackName = name
        self.tabs = tabs
        self.selectedTabID = tabs.contains { $0.id == selectedTabID }
            ? selectedTabID
            : tabs[0].id
        observeFirstTabDirectory()
    }

    @discardableResult
    func addTab() -> TerminalTab {
        let currentDirectory = tabs.first { $0.id == selectedTabID }?.workingDirectoryForNewTab()
        let tab = TerminalTab(number: tabs.count + 1, currentDirectory: currentDirectory)
        tabs.append(tab)
        selectedTabID = tab.id
        didChange?()
        return tab
    }

    func selectTab(_ tab: TerminalTab) {
        guard tabs.contains(where: { $0.id == tab.id }), selectedTabID != tab.id else {
            return
        }
        selectedTabID = tab.id
        didChange?()
    }

    func closeTab(_ tab: TerminalTab) {
        guard tabs.count > 1, let index = tabs.firstIndex(where: { $0.id == tab.id }) else {
            return
        }

        tabs.remove(at: index)
        if selectedTabID == tab.id {
            selectedTabID = tabs[min(index, tabs.count - 1)].id
        }
        observeFirstTabDirectory()
        didChange?()
    }

    private func observeFirstTabDirectory() {
        firstTabDirectoryObservation = tabs.first?.$currentDirectory
            .dropFirst()
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
    }
}

@MainActor
final class WorkspaceStore: ObservableObject {
    @Published private(set) var workspaces: [Workspace]
    @Published private(set) var selectedWorkspaceID: Workspace.ID

    private let stateURL: URL

    init(stateURL: URL? = nil) {
        self.stateURL = stateURL ?? Self.defaultStateURL

        if let restoredState = Self.loadState(from: self.stateURL) {
            let restoredWorkspaces = restoredState.workspaces.map { $0.workspace }
            workspaces = restoredWorkspaces
            selectedWorkspaceID = restoredWorkspaces.contains { $0.id == restoredState.selectedWorkspaceID }
                ? restoredState.selectedWorkspaceID
                : restoredWorkspaces[0].id
        } else {
            let initialWorkspaces = [
                Workspace(name: String(localized: "workspace.main", defaultValue: "Main")),
                Workspace(name: String(localized: "workspace.development", defaultValue: "Development")),
                Workspace(name: String(localized: "workspace.scratch", defaultValue: "Scratch"))
            ]
            workspaces = initialWorkspaces
            selectedWorkspaceID = initialWorkspaces[0].id
        }

        connectPersistenceCallbacks()
    }

    var selectedWorkspace: Workspace {
        workspaces.first { $0.id == selectedWorkspaceID } ?? workspaces[0]
    }

    func selectWorkspace(_ workspace: Workspace) {
        guard workspaces.contains(where: { $0.id == workspace.id }),
              selectedWorkspaceID != workspace.id else {
            return
        }
        selectedWorkspaceID = workspace.id
        save()
    }

    func addWorkspace() {
        let number = workspaces.count + 1
        let workspace = Workspace(
            name: String(localized: "workspace.numbered", defaultValue: "Workspace \(number)")
        )
        connectPersistenceCallback(to: workspace)
        workspaces.append(workspace)
        selectedWorkspaceID = workspace.id
        save()
    }

    func addTab() {
        selectedWorkspace.addTab()
    }

    func closeSelectedTab() {
        let workspace = selectedWorkspace
        guard let tab = workspace.tabs.first(where: { $0.id == workspace.selectedTabID }) else {
            return
        }

        workspace.closeTab(tab)
    }

    func save() {
        workspaces.forEach { workspace in
            workspace.tabs.forEach { $0.refreshCurrentDirectory() }
        }

        do {
            let directory = stateURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(PersistedWorkspaceState(store: self))
            try data.write(to: stateURL, options: .atomic)
        } catch {
            NSLog("SimpleCmux could not save workspace state: %@", error.localizedDescription)
        }
    }

    private func connectPersistenceCallbacks() {
        workspaces.forEach(connectPersistenceCallback)
    }

    private func connectPersistenceCallback(to workspace: Workspace) {
        workspace.didChange = { [weak self] in
            self?.save()
        }
    }

    private static func loadState(from url: URL) -> PersistedWorkspaceState? {
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(PersistedWorkspaceState.self, from: data),
              state.version == PersistedWorkspaceState.currentVersion,
              !state.workspaces.isEmpty,
              state.workspaces.allSatisfy({ !$0.tabs.isEmpty }) else {
            return nil
        }
        return state
    }

    private static var defaultStateURL: URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return applicationSupport
            .appendingPathComponent("SimpleCmux", isDirectory: true)
            .appendingPathComponent("workspaces.json")
    }
}

private struct PersistedWorkspaceState: Codable {
    static let currentVersion = 1

    let version: Int
    let selectedWorkspaceID: UUID
    let workspaces: [PersistedWorkspace]

    @MainActor
    init(store: WorkspaceStore) {
        version = Self.currentVersion
        selectedWorkspaceID = store.selectedWorkspaceID
        workspaces = store.workspaces.map(PersistedWorkspace.init)
    }
}

private struct PersistedWorkspace: Codable {
    let id: UUID
    let name: String
    let selectedTabID: UUID
    let tabs: [PersistedTerminalTab]

    init(workspace: Workspace) {
        id = workspace.id
        name = workspace.name
        selectedTabID = workspace.selectedTabID
        tabs = workspace.tabs.map(PersistedTerminalTab.init)
    }

    var workspace: Workspace {
        Workspace(
            id: id,
            name: name,
            tabs: tabs.enumerated().map { index, tab in tab.terminalTab(number: index + 1) },
            selectedTabID: selectedTabID
        )
    }
}

private struct PersistedTerminalTab: Codable {
    let id: UUID
    let title: String
    let currentDirectory: String?

    init(tab: TerminalTab) {
        id = tab.id
        title = tab.title
        currentDirectory = tab.currentDirectory
    }

    func terminalTab(number: Int) -> TerminalTab {
        TerminalTab(
            id: id,
            title: title,
            number: number,
            currentDirectory: currentDirectory
        )
    }
}
