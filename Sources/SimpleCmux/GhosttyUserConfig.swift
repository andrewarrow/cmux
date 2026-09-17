import AppKit
import Foundation

/// The small, startup-only subset of Ghostty configuration that SwiftTerm can
/// use directly. The file search order follows Ghostty's macOS defaults.
struct GhosttyUserConfig {
    private var values: [String: String] = [:]

    var fontFamily: String? { values["font-family"] }

    var fontSize: CGFloat? {
        guard let value = values["font-size"], let size = Double(value), size > 0 else {
            return nil
        }
        return CGFloat(size)
    }

    var backgroundColor: NSColor? { Self.color(from: values["background"]) }
    var foregroundColor: NSColor? { Self.color(from: values["foreground"]) }

    var workingDirectory: String? {
        guard let value = values["working-directory"],
              !value.isEmpty,
              value != "inherit" else {
            return nil
        }
        return value
    }

    static func load(
        fileManager: FileManager = .default,
        homeDirectory: URL? = nil
    ) -> Self {
        var config = Self()
        let homeDirectory = homeDirectory ?? fileManager.homeDirectoryForCurrentUser
        let home = homeDirectory.path
        let ghosttyDirectory = "\(home)/.config/ghostty"
        let appSupportDirectory = "\(home)/Library/Application Support/com.mitchellh.ghostty"

        var paths = [
            "\(ghosttyDirectory)/config",
            "\(ghosttyDirectory)/config.ghostty",
            "\(appSupportDirectory)/config.ghostty"
        ]

        let newConfig = "\(appSupportDirectory)/config.ghostty"
        let legacyConfig = "\(appSupportDirectory)/config"
        let newConfigSize = Self.fileSize(at: newConfig, fileManager: fileManager)
        if (newConfigSize == nil || newConfigSize == 0),
           let legacySize = Self.fileSize(at: legacyConfig, fileManager: fileManager),
           legacySize > 0 {
            paths.append(legacyConfig)
        }

        var includedPaths: [String] = []
        var loadedPaths = Set<String>()

        for path in paths {
            config.loadFile(
                at: path,
                fileManager: fileManager,
                includedPaths: &includedPaths,
                loadedPaths: &loadedPaths
            )
        }

        while !includedPaths.isEmpty {
            let path = includedPaths.removeFirst()
            config.loadFile(
                at: path,
                fileManager: fileManager,
                includedPaths: &includedPaths,
                loadedPaths: &loadedPaths
            )
        }

        return config
    }

    func resolvedWorkingDirectory(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> String {
        guard let workingDirectory else { return homeDirectory.path }
        let expanded = NSString(string: workingDirectory).expandingTildeInPath
        let path = URL(fileURLWithPath: expanded).standardizedFileURL.path
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return homeDirectory.path
        }
        return path
    }

    private mutating func loadFile(
        at path: String,
        fileManager: FileManager,
        includedPaths: inout [String],
        loadedPaths: inout Set<String>
    ) {
        let resolvedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        guard !loadedPaths.contains(resolvedPath),
              let contents = Self.contents(at: resolvedPath, fileManager: fileManager) else {
            return
        }
        loadedPaths.insert(resolvedPath)

        let parentDirectory = URL(fileURLWithPath: resolvedPath).deletingLastPathComponent()
        for rawLine in contents.components(separatedBy: .newlines) {
            guard let entry = Self.entry(from: rawLine) else { continue }
            if entry.key == "config-file" {
                includedPaths.append(Self.resolvePath(entry.value, relativeTo: parentDirectory))
            } else {
                values[entry.key] = entry.value
            }
        }
    }

    private static func entry(from rawLine: String) -> (key: String, value: String)? {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty, !line.hasPrefix("#"),
              let separator = line.firstIndex(of: "=") else {
            return nil
        }

        let key = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return nil }
        let rawValue = line[line.index(after: separator)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (key, unquote(rawValue))
    }

    private static func resolvePath(_ path: String, relativeTo directory: URL) -> String {
        let expanded = NSString(string: path).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded).standardizedFileURL.path
        }
        return directory.appendingPathComponent(expanded).standardizedFileURL.path
    }

    private static func unquote(_ value: String) -> String {
        guard value.count >= 2,
              (value.hasPrefix("\"") && value.hasSuffix("\""))
                || (value.hasPrefix("'") && value.hasSuffix("'")) else {
            return value
        }
        return String(value.dropFirst().dropLast())
    }

    private static func color(from value: String?) -> NSColor? {
        guard var value else { return nil }
        value.removeFirst(value.first == "#" ? 1 : 0)
        guard value.count == 6 || value.count == 8,
              let number = UInt32(value, radix: 16) else {
            return nil
        }

        let red = CGFloat((number >> (value.count == 8 ? 24 : 16)) & 0xFF) / 255
        let green = CGFloat((number >> (value.count == 8 ? 16 : 8)) & 0xFF) / 255
        let blue = CGFloat((number >> (value.count == 8 ? 8 : 0)) & 0xFF) / 255
        let alpha = value.count == 8 ? CGFloat(number & 0xFF) / 255 : 1
        return NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
    }

    private static func contents(at path: String, fileManager: FileManager) -> String? {
        guard let size = fileSize(at: path, fileManager: fileManager), size > 0 else {
            return nil
        }
        return try? String(contentsOfFile: path, encoding: .utf8)
    }

    private static func fileSize(at path: String, fileManager: FileManager) -> Int? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: path),
              let size = attributes[.size] as? NSNumber else {
            return nil
        }
        return size.intValue
    }
}
