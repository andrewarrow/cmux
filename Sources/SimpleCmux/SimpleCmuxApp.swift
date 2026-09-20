import AppKit
import SwiftUI

@main
struct SimpleCmuxApp: App {
    @StateObject private var store = WorkspaceStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
        .defaultSize(width: 1_000, height: 650)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(String(localized: "about.title", defaultValue: "About SimpleCmux")) {
                    let quote = String(
                        localized: "about.quote",
                        defaultValue: "“Perfection is achieved, not when there is nothing more to add, but when there is nothing left to take away.” — Antoine de Saint-Exupéry"
                    )
                    NSApp.orderFrontStandardAboutPanel(options: [
                        .credits: NSAttributedString(string: quote)
                    ])
                }
            }

            CommandGroup(after: .newItem) {
                Button(String(localized: "command.newTab", defaultValue: "New Tab")) {
                    store.addTab()
                }
                .keyboardShortcut("t", modifiers: .command)

                Button(String(localized: "command.closeTab", defaultValue: "Close Tab")) {
                    store.closeSelectedTab()
                }
                .keyboardShortcut("w", modifiers: .command)

                Button(String(localized: "command.previousTab", defaultValue: "Previous Tab")) {
                    store.selectPreviousTab()
                }
                .keyboardShortcut("{", modifiers: .command)

                Button(String(localized: "command.nextTab", defaultValue: "Next Tab")) {
                    store.selectNextTab()
                }
                .keyboardShortcut("}", modifiers: .command)

                Button(String(localized: "command.newWorkspace", defaultValue: "New Workspace")) {
                    store.addWorkspace()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Button(String(localized: "command.clearTerminal", defaultValue: "Clear Terminal")) {
                    (NSApp.keyWindow?.firstResponder as? SimpleTerminalView)?.clearToStart()
                }
                .keyboardShortcut("k", modifiers: .command)

                Button(String(localized: "command.copyAll", defaultValue: "Copy All")) {
                    (NSApp.keyWindow?.firstResponder as? SimpleTerminalView)?.copyAllText()
                }

                Button(String(localized: "command.exportText", defaultValue: "Export Text…")) {
                    (NSApp.keyWindow?.firstResponder as? SimpleTerminalView)?.exportText()
                }
                .keyboardShortcut("s", modifiers: .command)
            }
        }
    }
}
