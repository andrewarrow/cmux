import AppKit
import Foundation
import SwiftTerm
import SwiftUI

struct TerminalView: NSViewRepresentable {
    let tab: TerminalTab
    let isActive: Bool

    private static let userConfig = GhosttyUserConfig.load()

    func makeNSView(context: Context) -> SimpleTerminalView {
        let terminal = SimpleTerminalView(frame: .zero)
        terminal.shouldFocus = isActive
        let config = Self.userConfig
        let fontSize = config.fontSize ?? 13
        if let fontFamily = config.fontFamily,
           let configuredFont = NSFont(name: fontFamily, size: fontSize) {
            terminal.font = configuredFont
        } else {
            terminal.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        }
        terminal.nativeBackgroundColor = config.backgroundColor
            ?? NSColor(calibratedWhite: 0.08, alpha: 1)
        terminal.nativeForegroundColor = config.foregroundColor
            ?? NSColor(calibratedWhite: 0.92, alpha: 1)

        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        // A login, interactive shell attached to the PTY loads the user's normal
        // startup files, including ~/.zshrc for the default macOS zsh shell.
        let workingDirectory = config.resolvedWorkingDirectory()
        terminal.startProcess(executable: shell, args: ["-l", "-i"], currentDirectory: workingDirectory)
        return terminal
    }

    func updateNSView(_ nsView: SimpleTerminalView, context: Context) {
        nsView.shouldFocus = isActive
        nsView.focusIfNeeded()
    }

    static func dismantleNSView(_ nsView: SimpleTerminalView, coordinator: ()) {
        nsView.terminate()
    }
}

final class SimpleTerminalView: LocalProcessTerminalView {
    var shouldFocus = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        focusIfNeeded()
    }

    func focusIfNeeded() {
        guard shouldFocus, let window else { return }
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, self.shouldFocus else { return }
            window.makeFirstResponder(self)
        }
    }
}
