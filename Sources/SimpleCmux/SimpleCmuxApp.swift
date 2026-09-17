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
            CommandGroup(after: .newItem) {
                Button(String(localized: "command.newTab", defaultValue: "New Tab")) {
                    store.addTab()
                }
                .keyboardShortcut("t", modifiers: .command)

                Button(String(localized: "command.newWorkspace", defaultValue: "New Workspace")) {
                    store.addWorkspace()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Button(String(localized: "command.clearTerminal", defaultValue: "Clear Terminal")) {
                    (NSApp.keyWindow?.firstResponder as? SimpleTerminalView)?.clearScreenAndScrollback()
                }
                .keyboardShortcut("k", modifiers: .command)
            }
        }
    }
}
