import AppKit
import Darwin
import Foundation
import SwiftTerm
import SwiftUI

struct TerminalView: NSViewRepresentable {
    let tab: TerminalTab
    let isActive: Bool

    private static let userConfig = GhosttyUserConfig.load()

    final class Coordinator {
        let tab: TerminalTab

        init(tab: TerminalTab) {
            self.tab = tab
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(tab: tab)
    }

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
        let workingDirectory = existingDirectory(at: tab.currentDirectory)
            ?? config.resolvedWorkingDirectory()
        tab.currentDirectory = workingDirectory
        tab.currentDirectoryProvider = { [weak terminal, weak tab] in
            terminal?.currentWorkingDirectory() ?? tab?.currentDirectory
        }
        terminal.startProcess(executable: shell, args: ["-l", "-i"], currentDirectory: workingDirectory)
        return terminal
    }

    func updateNSView(_ nsView: SimpleTerminalView, context: Context) {
        nsView.shouldFocus = isActive
        nsView.focusIfNeeded()
    }

    static func dismantleNSView(_ nsView: SimpleTerminalView, coordinator: Coordinator) {
        coordinator.tab.currentDirectory = nsView.currentWorkingDirectory()
            ?? coordinator.tab.currentDirectory
        nsView.terminate()
    }

    private func existingDirectory(at path: String?) -> String? {
        guard let path else { return nil }
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }
        return path
    }
}

final class SimpleTerminalView: LocalProcessTerminalView {
    var shouldFocus = false

    func currentWorkingDirectory() -> String? {
        guard process.shellPid > 0 else { return nil }

        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            proc_pidinfo(process.shellPid, PROC_PIDVNODEPATHINFO, 0, pointer, size)
        }
        guard result == size else { return nil }

        return withUnsafePointer(to: &info.pvi_cdir.vip_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { path in
                String(cString: path)
            }
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers == .command,
           event.charactersIgnoringModifiers?.lowercased() == "k" {
            clearScreenAndScrollback()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    func clearScreenAndScrollback() {
        // ED 3 removes scrollback, ED 2 clears the visible screen, and CUP H
        // returns the cursor to the top-left without sending anything to the shell.
        terminal.feed(text: "\u{1B}[3J\u{1B}[2J\u{1B}[H")
        focusIfNeeded()
    }

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
