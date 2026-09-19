import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @State private var sidebarWidth: CGFloat = 220
    @State private var sidebarWidthAtDragStart: CGFloat?

    private let minimumSidebarWidth: CGFloat = 160
    private let maximumSidebarWidth: CGFloat = 420

    var body: some View {
        HStack(spacing: 0) {
            WorkspaceSidebar()
                .frame(width: sidebarWidth)

            SidebarResizeHandle { translation in
                let startingWidth = sidebarWidthAtDragStart ?? sidebarWidth
                sidebarWidthAtDragStart = startingWidth
                sidebarWidth = min(
                    max(startingWidth + translation, minimumSidebarWidth),
                    maximumSidebarWidth
                )
            } onEnded: {
                sidebarWidthAtDragStart = nil
            }

            ZStack {
                ForEach(store.workspaces) { workspace in
                    WorkspaceView(
                        workspace: workspace,
                        isWorkspaceActive: workspace.id == store.selectedWorkspaceID
                    )
                        .opacity(workspace.id == store.selectedWorkspaceID ? 1 : 0)
                        .allowsHitTesting(workspace.id == store.selectedWorkspaceID)
                }
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 760, minHeight: 460)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            store.save()
        }
        .onDisappear {
            store.save()
        }
    }
}

private struct SidebarResizeHandle: View {
    let onChanged: (CGFloat) -> Void
    let onEnded: () -> Void

    var body: some View {
        Rectangle()
            .fill(.clear)
            .frame(width: 8)
            .contentShape(Rectangle())
            .overlay {
                Divider()
            }
            .onHover { isHovering in
                if isHovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        onChanged(value.translation.width)
                    }
                    .onEnded { _ in
                        onEnded()
                    }
            )
            .accessibilityElement()
            .accessibilityLabel(String(localized: "sidebar.resize", defaultValue: "Resize sidebar"))
            .accessibilityHint(String(localized: "sidebar.resizeHint", defaultValue: "Drag left or right to resize the sidebar"))
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
            Group {
                if workspace.hasRunningCodex {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(String(localized: "sidebar.codexRunning", defaultValue: "Codex is running"))
                } else {
                    Image(systemName: "rectangle.3.group")
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                }
            }
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
    let isWorkspaceActive: Bool

    var body: some View {
        VStack(spacing: 0) {
            TabBar(workspace: workspace)
            Divider()

            ZStack {
                ForEach(workspace.tabs) { tab in
                    TerminalView(
                        tab: tab,
                        isActive: isWorkspaceActive && tab.id == workspace.selectedTabID
                    )
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
                TabItem(
                    tab: tab,
                    isSelected: tab.id == workspace.selectedTabID,
                    canClose: workspace.tabs.count > 1,
                    onSelect: { workspace.selectTab(tab) },
                    onClose: { workspace.closeTab(tab) }
                )
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

private struct TabItem: View {
    @ObservedObject var tab: TerminalTab
    let isSelected: Bool
    let canClose: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "terminal")
                .font(.caption)
            Text(tab.title)
                .lineLimit(1)
            if canClose {
                Button(action: onClose) {
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
        .background(isSelected ? Color.accentColor.opacity(0.18) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}
