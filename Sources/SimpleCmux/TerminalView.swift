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
        private weak var terminal: SimpleTerminalView?
        private var directoryTimer: Timer?

        init(tab: TerminalTab) {
            self.tab = tab
        }

        func startTrackingDirectory(of terminal: SimpleTerminalView) {
            self.terminal = terminal
            refreshDirectory()

            let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
                self?.refreshState()
            }
            RunLoop.main.add(timer, forMode: .common)
            directoryTimer = timer
        }

        func stopTrackingDirectory() {
            directoryTimer?.invalidate()
            directoryTimer = nil
            terminal = nil
        }

        private func refreshDirectory() {
            guard let directory = terminal?.currentWorkingDirectory() else { return }
            tab.updateCurrentDirectory(directory)
        }

        private func refreshState() {
            refreshDirectory()
            tab.updateCodexRunning(terminal?.hasRunningCodexProcess ?? false)
        }

        deinit {
            directoryTimer?.invalidate()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(tab: tab)
    }

    func makeNSView(context: Context) -> SimpleTerminalView {
        let terminal = SimpleTerminalView(frame: .zero)
        terminal.shouldFocus = isActive
        terminal.setAcceptsFileDrops(isActive)
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
        tab.updateCurrentDirectory(workingDirectory)
        tab.currentDirectoryProvider = { [weak terminal, weak tab] in
            terminal?.currentWorkingDirectory() ?? tab?.currentDirectory
        }
        terminal.startProcess(executable: shell, args: ["-l", "-i"], currentDirectory: workingDirectory)
        context.coordinator.startTrackingDirectory(of: terminal)
        return terminal
    }

    func updateNSView(_ nsView: SimpleTerminalView, context: Context) {
        nsView.shouldFocus = isActive
        nsView.setAcceptsFileDrops(isActive)
        nsView.focusIfNeeded()
    }

    static func dismantleNSView(_ nsView: SimpleTerminalView, coordinator: Coordinator) {
        coordinator.tab.updateCurrentDirectory(
            nsView.currentWorkingDirectory() ?? coordinator.tab.currentDirectory
        )
        coordinator.stopTrackingDirectory()
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
    private var acceptsFileDrops = false

    func setAcceptsFileDrops(_ acceptsFileDrops: Bool) {
        guard self.acceptsFileDrops != acceptsFileDrops else { return }
        self.acceptsFileDrops = acceptsFileDrops

        if acceptsFileDrops {
            registerForDraggedTypes([.fileURL])
        } else {
            unregisterDraggedTypes()
        }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        fileURLs(from: sender).isEmpty ? [] : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = fileURLs(from: sender)
        guard !urls.isEmpty else { return false }

        let paths = urls.map { shellQuoted($0.path) }.joined(separator: " ") + " "
        sendAsPaste(paths)
        window?.makeFirstResponder(self)
        return true
    }

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

    var hasRunningCodexProcess: Bool {
        ProcessTree.containsProcess(named: "codex", below: process.shellPid)
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

    private func fileURLs(from draggingInfo: NSDraggingInfo) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        return draggingInfo.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: options
        ) as? [URL] ?? []
    }

    private func shellQuoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func sendAsPaste(_ text: String) {
        if terminal.bracketedPasteMode {
            send(data: EscapeSequences.bracketedPasteStart[...])
        }
        send(txt: text)
        if terminal.bracketedPasteMode {
            send(data: EscapeSequences.bracketedPasteEnd[...])
        }
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

private enum ProcessTree {
    private struct ProcessInfo {
        let parentID: pid_t
        let name: String
        let arguments: [String]
    }

    static func containsProcess(named targetName: String, below rootPID: pid_t) -> Bool {
        guard rootPID > 0 else { return false }

        let processes = allProcesses()
        var childrenByParent: [pid_t: [pid_t]] = [:]
        for (pid, info) in processes {
            childrenByParent[info.parentID, default: []].append(pid)
        }

        var pending = childrenByParent[rootPID, default: []]
        while let pid = pending.popLast() {
            guard let info = processes[pid] else { continue }
            if info.name == targetName
                || info.name.hasPrefix("\(targetName)-")
                || info.arguments.contains(where: { argument in
                    let name = URL(fileURLWithPath: argument).lastPathComponent
                        .lowercased()
                    return name == targetName || name == "\(targetName).js"
                }) {
                return true
            }
            pending.append(contentsOf: childrenByParent[pid, default: []])
        }
        return false
    }

    private static func allProcesses() -> [pid_t: ProcessInfo] {
        let requestedSize = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard requestedSize > 0 else { return [:] }

        var pids = [pid_t](repeating: 0, count: Int(requestedSize) / MemoryLayout<pid_t>.size + 1)
        let actualSize = pids.withUnsafeMutableBytes { buffer in
            proc_listpids(
                UInt32(PROC_ALL_PIDS),
                0,
                buffer.baseAddress,
                Int32(buffer.count)
            )
        }
        guard actualSize > 0 else { return [:] }

        let count = Int(actualSize) / MemoryLayout<pid_t>.size
        var result: [pid_t: ProcessInfo] = [:]
        for pid in pids.prefix(count) where pid > 0 {
            var info = proc_bsdinfo()
            let infoSize = Int32(MemoryLayout<proc_bsdinfo>.size)
            let readSize = withUnsafeMutablePointer(to: &info) { pointer in
                proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, pointer, infoSize)
            }
            guard readSize == infoSize else { continue }

            let comm = info.pbi_comm
            let name = withUnsafePointer(to: comm) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: comm)) {
                    String(cString: $0)
                }
            }.lowercased()
            let arguments = name == "node" || name == "codex"
                ? processArguments(for: pid)
                : []
            result[pid] = ProcessInfo(
                parentID: pid_t(info.pbi_ppid),
                name: name,
                arguments: arguments
            )
        }
        return result
    }

    private static func processArguments(for pid: pid_t) -> [String] {
        var mib = [Int32(CTL_KERN), Int32(KERN_PROCARGS2), pid]
        var size = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0,
              size > MemoryLayout<Int32>.size else {
            return []
        }

        var bytes = [UInt8](repeating: 0, count: size)
        let result = bytes.withUnsafeMutableBytes { buffer in
            sysctl(&mib, UInt32(mib.count), buffer.baseAddress, &size, nil, 0)
        }
        guard result == 0 else { return [] }

        return bytes.dropFirst(MemoryLayout<Int32>.size)
            .split(separator: 0)
            .compactMap { String(bytes: $0, encoding: .utf8)?.lowercased() }
    }
}
