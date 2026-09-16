import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: WorkspaceStore

    var body: some View {
        HStack(spacing: 0) {
            WorkspaceSidebar()
                .frame(width: 220)

            Divider()

            ZStack {
                ForEach(store.workspaces) { workspace in
                    WorkspaceView(workspace: workspace)
                        .opacity(workspace.id == store.selectedWorkspaceID ? 1 : 0)
                        .allowsHitTesting(workspace.id == store.selectedWorkspaceID)
                }
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 760, minHeight: 460)
    }
}

private struct WorkspaceSidebar: View {
    @EnvironmentObject private var store: WorkspaceStore

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(String(localized: "sidebar.workspaces", defaultValue: "Workspaces"))
                    .font(.headline)
                Spacer()
                Button(action: store.addWorkspace) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help(String(localized: "sidebar.newWorkspace", defaultValue: "New workspace"))
                .accessibilityLabel(String(localized: "sidebar.newWorkspace", defaultValue: "New workspace"))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(store.workspaces) { workspace in
                        WorkspaceRow(workspace: workspace, isSelected: workspace.id == store.selectedWorkspaceID)
                            .onTapGesture {
                                store.selectWorkspace(workspace)
                            }
                    }
                }
                .padding(.horizontal, 8)
            }

            Spacer()
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct WorkspaceRow: View {
    @ObservedObject var workspace: Workspace
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "rectangle.3.group")
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(workspace.name)
                    .fontWeight(isSelected ? .semibold : .regular)
                Text(String(localized: "sidebar.tabCount", defaultValue: "\(workspace.tabs.count) tab"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .background(isSelected ? Color.accentColor.opacity(0.16) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

private struct WorkspaceView: View {
    @ObservedObject var workspace: Workspace

    var body: some View {
        VStack(spacing: 0) {
            TabBar(workspace: workspace)
            Divider()

            ZStack {
                ForEach(workspace.tabs) { tab in
                    TerminalView(tab: tab, isActive: tab.id == workspace.selectedTabID)
                        .opacity(tab.id == workspace.selectedTabID ? 1 : 0)
                        .allowsHitTesting(tab.id == workspace.selectedTabID)
                }
            }
            .background(Color.black)
        }
    }
}

private struct TabBar: View {
    @ObservedObject var workspace: Workspace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(workspace.tabs) { tab in
                HStack(spacing: 7) {
                    Image(systemName: "terminal")
                        .font(.caption)
                    Text(tab.title)
                        .lineLimit(1)
                    if workspace.tabs.count > 1 {
                        Button {
                            workspace.closeTab(tab)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption2)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(String(localized: "tab.close", defaultValue: "Close tab"))
                    }
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(tab.id == workspace.selectedTabID ? Color.accentColor.opacity(0.18) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
                .onTapGesture {
                    workspace.selectedTabID = tab.id
                }
            }

            Button {
                workspace.addTab()
            } label: {
                Image(systemName: "plus")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .help(String(localized: "tab.new", defaultValue: "New terminal tab"))
            .accessibilityLabel(String(localized: "tab.new", defaultValue: "New terminal tab"))

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
