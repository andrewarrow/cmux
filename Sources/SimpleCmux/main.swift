import AppKit
import SwiftTerm
import SwiftUI

@main
struct SimpleCmuxApp: App {
    var body: some Scene {
        WindowGroup {
            TerminalView()
                .frame(minWidth: 640, minHeight: 400)
        }
        .defaultSize(width: 960, height: 640)
    }
}

private struct TerminalView: NSViewRepresentable {
    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let terminal = SimpleTerminalView(frame: .zero)
        terminal.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        terminal.nativeBackgroundColor = NSColor(calibratedWhite: 0.08, alpha: 1)
        terminal.nativeForegroundColor = NSColor(calibratedWhite: 0.92, alpha: 1)

        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        terminal.startProcess(executable: shell, args: ["-l"])
        return terminal
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {}

    static func dismantleNSView(_ nsView: LocalProcessTerminalView, coordinator: ()) {
        nsView.terminate()
    }
}

private final class SimpleTerminalView: LocalProcessTerminalView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }
}
