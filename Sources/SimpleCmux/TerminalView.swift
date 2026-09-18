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
        private let codexActivityMonitor = CodexActivityMonitor()

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
            tab.updateCodexRunning(
                codexActivityMonitor.isPromptRunning(
                    below: terminal?.process.shellPid ?? 0
                )
            )
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

private final class CodexActivityMonitor {
    private var processID: pid_t?
    private var processStartedAt: Date?
    private var transcriptURL: URL?
    private var transcriptOffset: UInt64 = 0
    private var pendingTranscriptData = Data()
    private var promptIsRunning = false

    func isPromptRunning(below shellPID: pid_t) -> Bool {
        guard let process = ProcessTree.codexProcess(below: shellPID) else {
            reset()
            return false
        }

        if processID != process.id || processStartedAt != process.startedAt {
            reset(for: process)
        }

        if transcriptURL == nil {
            transcriptURL = findTranscript(for: process)
        }
        guard let transcriptURL else { return false }

        readNewEvents(from: transcriptURL)
        return promptIsRunning
    }

    private func reset(for process: ProcessTree.CodexProcess? = nil) {
        processID = process?.id
        processStartedAt = process?.startedAt
        transcriptURL = nil
        transcriptOffset = 0
        pendingTranscriptData.removeAll(keepingCapacity: true)
        promptIsRunning = false
    }

    private func findTranscript(for process: ProcessTree.CodexProcess) -> URL? {
        let sessionsRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true)
        let dates = Set([process.startedAt, Date()])
        var candidates: [(url: URL, startedAt: Date, modifiedAt: Date)] = []

        for date in dates {
            let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
            guard let year = components.year,
                  let month = components.month,
                  let day = components.day else {
                continue
            }
            let directory = sessionsRoot
                .appendingPathComponent(String(format: "%04d", year), isDirectory: true)
                .appendingPathComponent(String(format: "%02d", month), isDirectory: true)
                .appendingPathComponent(String(format: "%02d", day), isDirectory: true)
            guard let urls = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for url in urls where url.pathExtension == "jsonl" {
                guard let startedAt = transcriptStartDate(from: url.lastPathComponent),
                      transcriptWorkingDirectory(at: url) == process.currentDirectory else {
                    continue
                }
                let modifiedAt = (try? url.resourceValues(
                    forKeys: [.contentModificationDateKey]
                ).contentModificationDate) ?? .distantPast
                candidates.append((url, startedAt, modifiedAt))
            }
        }

        if let launchMatch = candidates.min(by: {
            abs($0.startedAt.timeIntervalSince(process.startedAt))
                < abs($1.startedAt.timeIntervalSince(process.startedAt))
        }), abs(launchMatch.startedAt.timeIntervalSince(process.startedAt)) < 30 {
            return launchMatch.url
        }

        guard process.arguments.contains("resume") else { return nil }
        return candidates
            .filter { $0.modifiedAt >= process.startedAt }
            .max(by: { $0.modifiedAt < $1.modifiedAt })?
            .url
    }

    private func transcriptStartDate(from filename: String) -> Date? {
        let timestampLength = 27
        guard filename.count >= timestampLength else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "'rollout-'yyyy-MM-dd'T'HH-mm-ss"
        return formatter.date(from: String(filename.prefix(timestampLength)))
    }

    private func transcriptWorkingDirectory(at url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 256 * 1024),
              let newline = data.firstIndex(of: 0x0A),
              let object = try? JSONSerialization.jsonObject(with: data[..<newline]),
              let envelope = object as? [String: Any],
              envelope["type"] as? String == "session_meta",
              let payload = envelope["payload"] as? [String: Any],
              let directory = payload["cwd"] as? String else {
            return nil
        }
        return URL(fileURLWithPath: directory).standardizedFileURL.path
    }

    private func readNewEvents(from url: URL) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }

        let fileSize = (try? handle.seekToEnd()) ?? 0
        if fileSize < transcriptOffset {
            transcriptOffset = 0
            pendingTranscriptData.removeAll(keepingCapacity: true)
            promptIsRunning = false
        }
        guard fileSize > transcriptOffset else { return }

        do {
            try handle.seek(toOffset: transcriptOffset)
            guard let newData = try handle.readToEnd(), !newData.isEmpty else { return }
            transcriptOffset += UInt64(newData.count)
            pendingTranscriptData.append(newData)
        } catch {
            return
        }

        let hasCompleteLastLine = pendingTranscriptData.last == 0x0A
        let lines = pendingTranscriptData.split(
            separator: 0x0A,
            omittingEmptySubsequences: false
        )
        let completeLines = lines.dropLast()
        pendingTranscriptData = hasCompleteLastLine
            ? Data()
            : Data(lines.last ?? Data.SubSequence())

        for line in completeLines where !line.isEmpty {
            guard let object = try? JSONSerialization.jsonObject(with: line),
                  let envelope = object as? [String: Any],
                  envelope["type"] as? String == "event_msg",
                  let payload = envelope["payload"] as? [String: Any],
                  let eventType = payload["type"] as? String else {
                continue
            }
            switch eventType {
            case "task_started":
                promptIsRunning = true
            case "task_complete", "turn_aborted":
                promptIsRunning = false
            default:
                break
            }
        }
    }
}

private enum ProcessTree {
    struct CodexProcess {
        let id: pid_t
        let startedAt: Date
        let currentDirectory: String
        let arguments: [String]
    }

    private struct ProcessInfo {
        let parentID: pid_t
        let name: String
        let arguments: [String]
        let startedAt: Date
    }

    static func codexProcess(below rootPID: pid_t) -> CodexProcess? {
        guard rootPID > 0 else { return nil }

        let processes = allProcesses()
        var childrenByParent: [pid_t: [pid_t]] = [:]
        for (pid, info) in processes {
            childrenByParent[info.parentID, default: []].append(pid)
        }

        var pending = childrenByParent[rootPID, default: []]
        var launcherMatch: CodexProcess?
        while let pid = pending.popLast() {
            guard let info = processes[pid] else { continue }
            let isNativeCodex = info.name == "codex" || info.name.hasPrefix("codex-")
            let isCodexLauncher = info.arguments.contains(where: { argument in
                    let name = URL(fileURLWithPath: argument).lastPathComponent
                        .lowercased()
                    return name == "codex" || name == "codex.js"
                })
            if (isNativeCodex || isCodexLauncher),
               let directory = currentDirectory(of: pid) {
                let match = CodexProcess(
                    id: pid,
                    startedAt: info.startedAt,
                    currentDirectory: directory,
                    arguments: info.arguments
                )
                if isNativeCodex { return match }
                launcherMatch = launcherMatch ?? match
            }
            pending.append(contentsOf: childrenByParent[pid, default: []])
        }
        return launcherMatch
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
                arguments: arguments,
                startedAt: Date(
                    timeIntervalSince1970: TimeInterval(info.pbi_start_tvsec)
                        + TimeInterval(info.pbi_start_tvusec) / 1_000_000
                )
            )
        }
        return result
    }

    private static func currentDirectory(of pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, pointer, size)
        }
        guard result == size else { return nil }

        return withUnsafePointer(to: &info.pvi_cdir.vip_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) {
                URL(fileURLWithPath: String(cString: $0)).standardizedFileURL.path
            }
        }
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
