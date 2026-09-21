import AppKit
import Carbon.HIToolbox
import Darwin
import Foundation
import GhosttyKit
import QuartzCore
import SwiftUI

private final class CodexActivityMonitor {
    private var processID: pid_t?
    private var processStartedAt: Date?
    private var transcriptURL: URL?
    private var transcriptOffset: UInt64 = 0
    private var pendingTranscriptData = Data()
    private var promptIsRunning = false
    private var promptSubmissionDeadline: Date?

    func notePromptSubmitted(for process: ProcessTree.CodexProcess) {
        if processID != process.id || processStartedAt != process.startedAt {
            reset(for: process)
        }
        promptIsRunning = true
        promptSubmissionDeadline = Date().addingTimeInterval(5)
    }

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
        guard let transcriptURL else {
            if let deadline = promptSubmissionDeadline, deadline >= Date() {
                return promptIsRunning
            }
            return false
        }

        readNewEvents(from: transcriptURL)
        if let deadline = promptSubmissionDeadline, deadline < Date() {
            promptSubmissionDeadline = nil
            promptIsRunning = false
        }
        return promptIsRunning
    }

    private func reset(for process: ProcessTree.CodexProcess? = nil) {
        processID = process?.id
        processStartedAt = process?.startedAt
        transcriptURL = nil
        transcriptOffset = 0
        pendingTranscriptData.removeAll(keepingCapacity: true)
        promptIsRunning = false
        promptSubmissionDeadline = nil
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
                promptSubmissionDeadline = nil
                promptIsRunning = true
            case "task_complete", "turn_aborted":
                if promptSubmissionDeadline == nil {
                    promptIsRunning = false
                }
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

/// The small branch keeps cmux's terminal boundary but uses the same embedded
/// libghostty surface as the main branch. Ghostty owns the PTY, parser,
/// renderer, selection model, key encoding, and resize/SIGWINCH behavior.
private final class GhosttyTickDriver {
    private let lock = NSLock()
    private var isScheduled = false
    private var handler: (() -> Void)?

    func install(_ handler: @escaping () -> Void) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    func clear() {
        lock.lock()
        handler = nil
        lock.unlock()
    }

    func wakeup() {
        lock.lock()
        guard !isScheduled else {
            lock.unlock()
            return
        }
        isScheduled = true
        lock.unlock()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.isScheduled = false
            let handler = self.handler
            self.lock.unlock()
            handler?()
        }
    }
}

@MainActor
private final class GhosttyRuntime {
    static let shared = GhosttyRuntime()

    let app: ghostty_app_t
    private let tickDriver = GhosttyTickDriver()

    private init() {
        precondition(
            ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv) == GHOSTTY_SUCCESS,
            "Unable to initialize Ghostty"
        )

        guard let config = ghostty_config_new() else {
            fatalError("Unable to create Ghostty configuration")
        }
        ghostty_config_load_default_files(config)
        ghostty_config_finalize(config)

        var runtime = ghostty_runtime_config_s(
            userdata: Unmanaged.passUnretained(tickDriver).toOpaque(),
            supports_selection_clipboard: true,
            wakeup_cb: { userdata in
                guard let userdata else { return }
                Unmanaged<GhosttyTickDriver>
                    .fromOpaque(userdata)
                    .takeUnretainedValue()
                    .wakeup()
            },
            action_cb: { _, _, _ in false },
            read_clipboard_cb: { _, _, _ in false },
            confirm_read_clipboard_cb: { _, _, _, _ in },
            write_clipboard_cb: { _, _, _, _, _ in },
            close_surface_cb: { _, _ in },
            tmux_control_cb: nil
        )
        guard let app = ghostty_app_new(&runtime, config) else {
            ghostty_config_free(config)
            fatalError("Unable to create Ghostty application")
        }
        ghostty_config_free(config)
        self.app = app
        ghostty_app_set_focus(app, true)
        tickDriver.install { [weak self] in
            guard let self else { return }
            MainActor.assumeIsolated {
                ghostty_app_tick(self.app)
            }
        }
        tickDriver.wakeup()
    }

    deinit {
        tickDriver.clear()
        ghostty_app_free(app)
    }
}

struct TerminalView: NSViewRepresentable {
    let tab: TerminalTab
    let isActive: Bool

    private static let userConfig = GhosttyUserConfig.load()

    final class Coordinator {
        let tab: TerminalTab
        private weak var terminal: GhosttyTerminalView?
        private var directoryTimer: Timer?
        private let codexActivityMonitor = CodexActivityMonitor()

        init(tab: TerminalTab) { self.tab = tab }

        func startTrackingDirectory(of terminal: GhosttyTerminalView) {
            self.terminal = terminal
            refreshState()
            let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
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

        private func refreshState() {
            if let directory = terminal?.currentWorkingDirectory() {
                tab.updateCurrentDirectory(directory)
            }
            let shellPID = terminal?.foregroundProcessID ?? 0
            tab.updateCodexRunning(codexActivityMonitor.isPromptRunning(below: shellPID))
        }

        deinit { directoryTimer?.invalidate() }
    }

    func makeCoordinator() -> Coordinator { Coordinator(tab: tab) }

    func makeNSView(context: Context) -> GhosttyTerminalView {
        let workingDirectory = existingDirectory(at: tab.currentDirectory)
            ?? Self.userConfig.resolvedWorkingDirectory()
        tab.updateCurrentDirectory(workingDirectory)
        let terminal = GhosttyTerminalView(
            workingDirectory: workingDirectory,
            fontSize: Float(Self.userConfig.fontSize ?? 13)
        )
        terminal.setActive(isActive)
        tab.currentDirectoryProvider = { [weak terminal, weak tab] in
            terminal?.currentWorkingDirectory() ?? tab?.currentDirectory
        }
        context.coordinator.startTrackingDirectory(of: terminal)
        return terminal
    }

    func updateNSView(_ nsView: GhosttyTerminalView, context: Context) {
        nsView.setActive(isActive)
        nsView.focusIfNeeded()
        if isActive { nsView.setNeedsDisplay(nsView.bounds) }
    }

    static func dismantleNSView(_ nsView: GhosttyTerminalView, coordinator: Coordinator) {
        coordinator.tab.updateCurrentDirectory(
            nsView.currentWorkingDirectory() ?? coordinator.tab.currentDirectory
        )
        coordinator.stopTrackingDirectory()
    }

    private func existingDirectory(at path: String?) -> String? {
        guard let path else { return nil }
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }
        return path
    }
}

final class GhosttyTerminalView: NSView, NSTextInputClient {
    private var surface: ghostty_surface_t?
    private var keyTextAccumulator: [String]?
    var shouldFocus = false

    override func makeBackingLayer() -> CALayer {
        let metalLayer = CAMetalLayer()
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = false
        metalLayer.isOpaque = false
        return metalLayer
    }

    func setActive(_ active: Bool) {
        shouldFocus = active
        isHidden = !active
        if let surface {
            ghostty_surface_set_focus(surface, active)
            ghostty_surface_set_occlusion(surface, !active)
        }
        if active { focusIfNeeded() }
    }

    init(workingDirectory: String, fontSize: Float) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        let runtime = GhosttyRuntime.shared
        var config = ghostty_surface_config_new()
        config.userdata = Unmanaged.passUnretained(self).toOpaque()
        config.platform_tag = GHOSTTY_PLATFORM_MACOS
        config.platform = ghostty_platform_u(macos: ghostty_platform_macos_s(
            nsview: Unmanaged.passUnretained(self).toOpaque()
        ))
        config.scale_factor = Double(NSScreen.main?.backingScaleFactor ?? 2)
        config.font_size = fontSize
        config.context = GHOSTTY_SURFACE_CONTEXT_TAB

        self.surface = workingDirectory.withCString { directory in
            config.working_directory = directory
            return ghostty_surface_new(runtime.app, &config)
        }
        guard surface != nil else {
            layer?.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 1).cgColor
            return
        }
        ghostty_surface_set_focus(surface, true)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        if let surface { ghostty_surface_free(surface) }
    }

    var foregroundProcessID: pid_t {
        guard let surface else { return 0 }
        return pid_t(ghostty_surface_foreground_pid(surface))
    }

    func currentWorkingDirectory() -> String? {
        let pid = foregroundProcessID
        guard pid > 0 else { return nil }
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, $0, size)
        }
        guard result == size else { return nil }
        return withUnsafePointer(to: &info.pvi_cdir.vip_path) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) {
                String(cString: $0)
            }
        }
    }

    func focusIfNeeded() {
        guard shouldFocus, let window else { return }
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, self.shouldFocus else { return }
            if window.firstResponder !== self {
                _ = window.makeFirstResponder(self)
            }
            if window.firstResponder === self, let surface = self.surface {
                ghostty_surface_set_focus(surface, true)
            }
        }
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result, let surface { ghostty_surface_set_focus(surface, true) }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result, let surface { ghostty_surface_set_focus(surface, false) }
        return result
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateSurfaceSize()
        focusIfNeeded()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateSurfaceSize()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateSurfaceSize()
    }

    private func updateSurfaceSize() {
        guard let surface, bounds.width > 0, bounds.height > 0 else { return }
        let backing = convertToBacking(bounds).size
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        layer?.contentsScale = scale
        ghostty_surface_set_content_scale(surface, scale, scale)
        ghostty_surface_set_size(surface, UInt32(backing.width), UInt32(backing.height))
    }

    override func keyDown(with event: NSEvent) {
        guard let surface else {
            interpretKeyEvents([event])
            return
        }

        // Let AppKit perform keyboard-layout and IME translation first. Text
        // committed by the input method is accumulated and sent as part of the
        // same Ghostty key event, matching the native Ghostty AppKit view.
        let translatedMods = ghostty_surface_key_translation_mods(
            surface,
            ghosttyMods(event.modifierFlags)
        )
        let translatedFlags = modifierFlags(for: translatedMods, basedOn: event.modifierFlags)
        let translatedEvent: NSEvent
        if translatedFlags == event.modifierFlags {
            translatedEvent = event
        } else {
            translatedEvent = NSEvent.keyEvent(
                with: event.type,
                location: event.locationInWindow,
                modifierFlags: translatedFlags,
                timestamp: event.timestamp,
                windowNumber: event.windowNumber,
                context: nil,
                characters: event.characters(byApplyingModifiers: translatedFlags) ?? "",
                charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "",
                isARepeat: event.isARepeat,
                keyCode: event.keyCode
            ) ?? event
        }

        keyTextAccumulator = []
        interpretKeyEvents([translatedEvent])
        let committedText = keyTextAccumulator?.joined()
        keyTextAccumulator = nil

        let action = event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS
        sendKey(
            event,
            action: action,
            translationFlags: translatedFlags,
            text: committedText ?? keyText(for: event, applying: translatedFlags),
            composing: false
        )
    }

    override func keyUp(with event: NSEvent) { sendKey(event, action: GHOSTTY_ACTION_RELEASE) }

    private func sendKey(
        _ event: NSEvent,
        action: ghostty_input_action_e,
        translationFlags: NSEvent.ModifierFlags? = nil,
        text: String? = nil,
        composing: Bool = false
    ) {
        guard let surface else { return }
        var key = ghostty_input_key_s()
        key.action = action
        key.mods = ghosttyMods(event.modifierFlags)
        key.consumed_mods = ghosttyMods(
            (translationFlags ?? event.modifierFlags).subtracting([.control, .command])
        )
        key.keycode = UInt32(event.keyCode)
        // AppKit raises an exception if charactersByApplyingModifiers: is
        // called for a modifier-only (flagsChanged) event. Modifier events
        // do not have a key text/codepoint to send anyway.
        if event.type != .flagsChanged {
            key.unshifted_codepoint = event.characters(byApplyingModifiers: [])?.unicodeScalars.first?.value ?? 0
        }
        key.composing = composing
        let characters = action == GHOSTTY_ACTION_RELEASE ? nil : (text ?? event.characters)
        if let characters {
            characters.withCString { key.text = $0; _ = ghostty_surface_key(surface, key) }
        } else {
            _ = ghostty_surface_key(surface, key)
        }
    }

    private func modifierFlags(
        for mods: ghostty_input_mods_e,
        basedOn original: NSEvent.ModifierFlags
    ) -> NSEvent.ModifierFlags {
        var flags = original
        for flag in [NSEvent.ModifierFlags.shift, .control, .option, .command] {
            if ghosttyMods(flags: mods).contains(flag) {
                flags.insert(flag)
            } else {
                flags.remove(flag)
            }
        }
        return flags
    }

    private func ghosttyMods(flags: ghostty_input_mods_e) -> NSEvent.ModifierFlags {
        var result: NSEvent.ModifierFlags = []
        if flags.rawValue & GHOSTTY_MODS_SHIFT.rawValue != 0 { result.insert(.shift) }
        if flags.rawValue & GHOSTTY_MODS_CTRL.rawValue != 0 { result.insert(.control) }
        if flags.rawValue & GHOSTTY_MODS_ALT.rawValue != 0 { result.insert(.option) }
        if flags.rawValue & GHOSTTY_MODS_SUPER.rawValue != 0 { result.insert(.command) }
        return result
    }

    private func keyText(
        for event: NSEvent,
        applying flags: NSEvent.ModifierFlags
    ) -> String? {
        guard let characters = event.characters else { return nil }
        if let scalar = characters.unicodeScalars.first, scalar.value < 0x20 {
            return event.characters(byApplyingModifiers: flags.subtracting(.control))
        }
        if let scalar = characters.unicodeScalars.first,
           (0xF700...0xF8FF).contains(scalar.value) {
            return nil
        }
        return characters
    }

    private func ghosttyMods(_ flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
        var raw = UInt32(GHOSTTY_MODS_NONE.rawValue)
        if flags.contains(.shift) { raw |= GHOSTTY_MODS_SHIFT.rawValue }
        if flags.contains(.control) { raw |= GHOSTTY_MODS_CTRL.rawValue }
        if flags.contains(.option) { raw |= GHOSTTY_MODS_ALT.rawValue }
        if flags.contains(.command) { raw |= GHOSTTY_MODS_SUPER.rawValue }
        if flags.contains(.capsLock) { raw |= GHOSTTY_MODS_CAPS.rawValue }
        return ghostty_input_mods_e(raw)
    }

    override func mouseDown(with event: NSEvent) {
        guard let surface else { return }
        _ = window?.makeFirstResponder(self)
        ghostty_surface_set_focus(surface, true)
        ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_LEFT, ghosttyMods(event.modifierFlags))
    }

    override func flagsChanged(with event: NSEvent) {
        guard surface != nil else { return }
        let modifier: UInt32
        switch event.keyCode {
        case 0x39: modifier = GHOSTTY_MODS_CAPS.rawValue
        case 0x38, 0x3C: modifier = GHOSTTY_MODS_SHIFT.rawValue
        case 0x3B, 0x3E: modifier = GHOSTTY_MODS_CTRL.rawValue
        case 0x3A, 0x3D: modifier = GHOSTTY_MODS_ALT.rawValue
        case 0x37, 0x36: modifier = GHOSTTY_MODS_SUPER.rawValue
        default: return
        }
        let mods = ghosttyMods(event.modifierFlags)
        let action: ghostty_input_action_e = mods.rawValue & modifier == 0
            ? GHOSTTY_ACTION_RELEASE
            : GHOSTTY_ACTION_PRESS
        sendKey(event, action: action)
    }

    override func mouseUp(with event: NSEvent) {
        guard let surface else { return }
        ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_LEFT, ghosttyMods(event.modifierFlags))
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let surface else { return super.rightMouseDown(with: event) }
        if !ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_RIGHT, ghosttyMods(event.modifierFlags)) {
            super.rightMouseDown(with: event)
        }
    }

    override func rightMouseUp(with event: NSEvent) {
        guard let surface else { return super.rightMouseUp(with: event) }
        if !ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_RIGHT, ghosttyMods(event.modifierFlags)) {
            super.rightMouseUp(with: event)
        }
    }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseMoved(with event: NSEvent) { sendMousePosition(event) }
    override func mouseDragged(with event: NSEvent) { sendMousePosition(event) }

    private func sendMousePosition(_ event: NSEvent) {
        guard let surface else { return }
        let point = convert(event.locationInWindow, from: nil)
        ghostty_surface_mouse_pos(
            surface,
            Double(point.x),
            Double(bounds.height - point.y),
            ghosttyMods(event.modifierFlags)
        )
    }

    override func scrollWheel(with event: NSEvent) {
        guard let surface else { return }
        ghostty_surface_mouse_scroll(surface, event.scrollingDeltaX, event.scrollingDeltaY, Int32(event.phase.rawValue))
    }

    func clearToStart() {
        guard let surface else { return }
        "\u{0c}".withCString { ghostty_surface_text(surface, $0, 1) }
    }

    func copyAllText() {
        guard let surface else { return }
        var text = ghostty_text_s()
        let size = ghostty_surface_size(surface)
        let selection = ghostty_selection_s(
            top_left: ghostty_point_s(tag: GHOSTTY_POINT_VIEWPORT, coord: GHOSTTY_POINT_COORD_TOP_LEFT, x: 0, y: 0),
            bottom_right: ghostty_point_s(tag: GHOSTTY_POINT_VIEWPORT, coord: GHOSTTY_POINT_COORD_BOTTOM_RIGHT, x: UInt32(size.columns), y: UInt32(size.rows)),
            rectangle: false
        )
        guard ghostty_surface_read_text(surface, selection, &text), let ptr = text.text else { return }
        let value = String(data: Data(bytes: ptr, count: Int(text.text_len)), encoding: .utf8) ?? ""
        ghostty_surface_free_text(surface, &text)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    func exportText() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "terminal.txt"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            var text = ""
            if let surface = self?.surface {
                var cText = ghostty_text_s()
                let size = ghostty_surface_size(surface)
                let selection = ghostty_selection_s(
                    top_left: ghostty_point_s(tag: GHOSTTY_POINT_VIEWPORT, coord: GHOSTTY_POINT_COORD_TOP_LEFT, x: 0, y: 0),
                    bottom_right: ghostty_point_s(tag: GHOSTTY_POINT_VIEWPORT, coord: GHOSTTY_POINT_COORD_BOTTOM_RIGHT, x: UInt32(size.columns), y: UInt32(size.rows)),
                    rectangle: false
                )
                if ghostty_surface_read_text(surface, selection, &cText), let ptr = cText.text {
                    text = String(data: Data(bytes: ptr, count: Int(cText.text_len)), encoding: .utf8) ?? ""
                    ghostty_surface_free_text(surface, &cText)
                }
            }
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if modifiers == .command, let command = event.charactersIgnoringModifiers?.lowercased() {
            switch command {
            case "c":
                return copySelectionIfPresent()
            case "v":
                pasteFromPasteboard()
                return true
            case "x":
                return copySelectionIfPresent()
            default:
                break
            }
        }
        if modifiers == .command, event.charactersIgnoringModifiers?.lowercased() == "k" {
            clearToStart()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    private func copySelectionIfPresent() -> Bool {
        guard let surface, ghostty_surface_has_selection(surface) else { return false }
        var text = ghostty_text_s()
        guard ghostty_surface_read_selection(surface, &text), let ptr = text.text else { return false }
        let value = String(data: Data(bytes: ptr, count: Int(text.text_len)), encoding: .utf8) ?? ""
        ghostty_surface_free_text(surface, &text)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        return true
    }

    private func pasteFromPasteboard() {
        guard let surface, let value = NSPasteboard.general.string(forType: .string) else { return }
        value.withCString { ghostty_surface_text(surface, $0, UInt(value.utf8.count)) }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])?.isEmpty == false ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty else { return false }
        let text = urls.map { "'" + $0.path.replacingOccurrences(of: "'", with: "'\\''") + "'" }.joined(separator: " ") + " "
        guard let surface else { return false }
        text.withCString { ghostty_surface_text(surface, $0, UInt(text.utf8.count)) }
        window?.makeFirstResponder(self)
        return true
    }

    // NSTextInputClient: direct key events above cover normal shell input;
    // these methods keep IME and dead-key input AppKit-compatible.
    func insertText(_ string: Any, replacementRange: NSRange) {
        let text: String
        if let value = string as? String {
            text = value
        } else if let value = string as? NSAttributedString {
            text = value.string
        } else {
            return
        }
        if keyTextAccumulator != nil {
            keyTextAccumulator?.append(text)
            return
        }
        guard let surface else { return }
        text.withCString { ghostty_surface_text_input(surface, $0, UInt(text.utf8.count)) }
    }
    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {}
    func unmarkText() {}
    func selectedRange() -> NSRange { NSRange(location: NSNotFound, length: 0) }
    func markedRange() -> NSRange { NSRange(location: NSNotFound, length: 0) }
    func hasMarkedText() -> Bool { false }
    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }
    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? { nil }
    func characterIndex(for point: NSPoint) -> Int { 0 }
    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect { .zero }
    override func doCommand(by selector: Selector) {}
}
