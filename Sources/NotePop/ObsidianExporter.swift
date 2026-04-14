import Foundation

enum ExportError: LocalizedError {
    case notConfigured
    case failedToLaunch(String)
    case nonZeroExit(code: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Obsidian export is not configured. Open Settings (Cmd+,) and set CLI path/args."
        case .failedToLaunch(let message):
            return "Failed to run Obsidian CLI: \(message)"
        case .nonZeroExit(let code, let stderr):
            if stderr.isEmpty {
                return "Obsidian CLI exited with code \(code)."
            }
            return "Obsidian CLI exited with code \(code): \(stderr)"
        }
    }
}

final class ObsidianExporter {
    private let settings: SettingsStore

    init(settings: SettingsStore) {
        self.settings = settings
    }

    /// Runs the configured Obsidian CLI command.
    /// - Note: Args are treated like a shell (quotes supported). `{header}` is replaced with the configured header.
    func export(noteText: String) async throws {
        let snapshot = await MainActor.run {
            (
                settings.obsidianCLIPath.trimmingCharacters(in: .whitespacesAndNewlines),
                settings.obsidianCLIArgs.trimmingCharacters(in: .whitespacesAndNewlines),
                settings.dailyHeader
            )
        }

        let (cliPathRaw, argsTemplate, dailyHeader) = snapshot

        guard !cliPathRaw.isEmpty, !argsTemplate.isEmpty else {
            throw ExportError.notConfigured
        }

        let cliPathExpanded = (cliPathRaw as NSString).expandingTildeInPath
        let replaced = argsTemplate.replacingOccurrences(of: "{header}", with: dailyHeader)

        try await Task.detached(priority: .userInitiated) {
            let args = try ShellWords.split(replaced)

            let (executableURL, finalArgs) = resolveExecutableAndArgs(cliPathExpanded: cliPathExpanded, args: args)

            let process = Process()
            process.executableURL = executableURL
            process.arguments = finalArgs

            let stdinPipe = Pipe()
            process.standardInput = stdinPipe

            let stderrPipe = Pipe()
            process.standardError = stderrPipe

            do {
                try process.run()
            } catch {
                throw ExportError.failedToLaunch(error.localizedDescription)
            }

            if let data = (noteText + "\n").data(using: .utf8) {
                stdinPipe.fileHandleForWriting.write(data)
            }
            try? stdinPipe.fileHandleForWriting.close()

            process.waitUntilExit()

            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrString = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if process.terminationStatus != 0 {
                throw ExportError.nonZeroExit(code: process.terminationStatus, stderr: stderrString)
            }
        }.value
    }
}

private func resolveExecutableAndArgs(cliPathExpanded: String, args: [String]) -> (URL, [String]) {
    // If the user provided a full/relative path, execute it directly.
    if cliPathExpanded.contains("/") {
        return (URL(fileURLWithPath: cliPathExpanded), args)
    }
    // Otherwise resolve via PATH using /usr/bin/env.
    return (URL(fileURLWithPath: "/usr/bin/env"), [cliPathExpanded] + args)
}

enum ShellWords {
    enum SplitError: LocalizedError {
        case unterminatedQuote
        var errorDescription: String? { "Invalid arguments: unterminated quote" }
    }

    /// Minimal shell-like splitting supporting single/double quotes and backslash escaping.
    static func split(_ string: String) throws -> [String] {
        var result: [String] = []
        var current = ""

        enum State { case normal, singleQuote, doubleQuote }
        var state: State = .normal

        var iterator = string.makeIterator()
        while let char = iterator.next() {
            switch state {
            case .normal:
                if char == " " || char == "\t" || char == "\n" {
                    if !current.isEmpty {
                        result.append(current)
                        current = ""
                    }
                    continue
                }
                if char == "\"" {
                    state = .doubleQuote
                    continue
                }
                if char == "'" {
                    state = .singleQuote
                    continue
                }
                if char == "\\" {
                    if let next = iterator.next() {
                        current.append(next)
                    }
                    continue
                }
                current.append(char)

            case .singleQuote:
                if char == "'" {
                    state = .normal
                    continue
                }
                current.append(char)

            case .doubleQuote:
                if char == "\"" {
                    state = .normal
                    continue
                }
                if char == "\\" {
                    if let next = iterator.next() {
                        current.append(next)
                    }
                    continue
                }
                current.append(char)
            }
        }

        if state != .normal {
            throw SplitError.unterminatedQuote
        }

        if !current.isEmpty {
            result.append(current)
        }
        return result
    }
}
