import Foundation

enum ExportError: LocalizedError {
    case obsidianNotFound
    case failedToLaunch(String)
    case nonZeroExit(code: Int32, stderr: String)
    case invalidDailyPath(String)
    case invalidVaultPath(String)

    var errorDescription: String? {
        switch self {
        case .obsidianNotFound:
            return "Could not find the `obsidian` CLI. Install/update Obsidian to a version with CLI support, and ensure apps can see it in PATH (common locations: /opt/homebrew/bin, /usr/local/bin)."
        case .failedToLaunch(let message):
            return "Failed to run Obsidian CLI: \(message)"
        case .nonZeroExit(let code, let stderr):
            if stderr.isEmpty {
                return "Obsidian CLI exited with code \(code)."
            }
            return "Obsidian CLI exited with code \(code): \(stderr)"
        case .invalidDailyPath(let value):
            return "Obsidian CLI returned an invalid daily note path: \(value)"
        case .invalidVaultPath(let value):
            return "Obsidian CLI returned an invalid vault path: \(value)"
        }
    }
}

final class ObsidianExporter {
    private let settings: SettingsStore

    init(settings: SettingsStore) {
        self.settings = settings
    }

    /// Inserts the note into today’s daily note under the configured header.
    ///
    /// Uses the Obsidian CLI:
    /// - `obsidian daily:path`
    /// - `obsidian daily:read`
    /// - `obsidian create path=<dailyPath> overwrite content=<...>`
    func export(noteText: String) async throws {
        let dailyHeader = await MainActor.run { settings.dailyHeader }
        let trimmedNote = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNote.isEmpty else { return }

        try await Task.detached(priority: .userInitiated) { () throws -> Void in
            let dailyPathOut = try ObsidianCLI.runAndCaptureStdout(arguments: ["daily:path"])
            let dailyPathRaw = ObsidianCLIOutput.stripNoise(dailyPathOut)
            let dailyPath = ObsidianCLIOutput.extractDailyPath(from: dailyPathRaw)
            guard !dailyPath.isEmpty else { throw ExportError.invalidDailyPath(dailyPathRaw) }

            let currentOut = try ObsidianCLI.runAndCaptureStdout(arguments: ["daily:read"])
            let current = ObsidianCLIOutput.stripNoise(currentOut)
                .replacingOccurrences(of: "\r\n", with: "\n")

            let updated = MarkdownDailyNoteInserter.insert(
                note: trimmedNote,
                into: current,
                underHeader: dailyHeader
            )

            // Prefer CLI write-back for small-ish notes; fall back to direct file write for large notes.
            // This avoids command-line length limits with huge daily notes.
            let encoded = ObsidianCLI.encodeContentValue(updated)
            if encoded.utf8.count <= 180_000 {
                _ = try ObsidianCLI.runAndCaptureStdout(arguments: [
                    "create",
                    "path=\(dailyPath)",
                    "overwrite",
                    "content=\(encoded)"
                ])
            } else {
                let vaultOut = try ObsidianCLI.runAndCaptureStdout(arguments: ["vault", "info=path"])
                let vaultPathRaw = ObsidianCLIOutput.stripNoise(vaultOut)
                let vaultPath = ObsidianCLIOutput.extractLastNonEmptyLine(from: vaultPathRaw)
                guard !vaultPath.isEmpty else { throw ExportError.invalidVaultPath(vaultPathRaw) }

                let dailyURL: URL
                if dailyPath.hasPrefix("/") {
                    dailyURL = URL(fileURLWithPath: dailyPath)
                } else {
                    dailyURL = URL(fileURLWithPath: vaultPath).appendingPathComponent(dailyPath)
                }

                let dirURL = dailyURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
                let data = Data(updated.utf8)
                try data.write(to: dailyURL, options: .atomic)
            }
        }.value
    }
}

enum ObsidianCLIOutput {
    /// Some Obsidian versions print informational lines (installer/asar messages) before the real output.
    /// Strip known prefixes so we don't treat them as daily note content or paths.
    static func stripNoise(_ output: String) -> String {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let filtered = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return true }
            if trimmed.contains("Loading updated app package") { return false }
            if trimmed.contains("installer is out of date") { return false }
            return true
        }
        return filtered.joined(separator: "\n")
    }

    static func extractDailyPath(from output: String) -> String {
        let candidates = output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }

        // Prefer a line that looks like a markdown path.
        if let md = candidates.last(where: { $0.lowercased().hasSuffix(".md") }) {
            return md
        }
        // Fall back to the last non-empty line.
        return candidates.last ?? ""
    }

    static func extractLastNonEmptyLine(from output: String) -> String {
        output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .last ?? ""
    }
}

enum ObsidianCLI {
    private static let resolvedObsidianURL: URL? = {
        // Resolve once per launch; if it fails, we keep nil and raise on use.
        try? resolveObsidianExecutableURL()
    }()

    static func runAndCaptureStdout(arguments: [String]) throws -> String {
        guard let obsidianURL = resolvedObsidianURL else {
            throw ExportError.obsidianNotFound
        }

        let (stdout, stderr, status) = try runProcess(
            executableURL: obsidianURL,
            arguments: arguments,
            environment: mergedGUIPathEnvironment()
        )

        if status != 0 {
            throw ExportError.nonZeroExit(code: status, stderr: stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return stdout
    }

    private static func resolveObsidianExecutableURL() throws -> URL {
        // 1) Common install locations
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates: [String] = [
            "/opt/homebrew/bin/obsidian",
            "/usr/local/bin/obsidian",
            "\(home)/.local/bin/obsidian",
            "\(home)/bin/obsidian"
        ]

        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }

        // 2) /usr/bin/which with a GUI-friendly PATH
        do {
            let (stdout, _, status) = try runProcess(
                executableURL: URL(fileURLWithPath: "/usr/bin/which"),
                arguments: ["obsidian"],
                environment: mergedGUIPathEnvironment()
            )
            if status == 0 {
                let found = stdout
                    .split(separator: "\n", omittingEmptySubsequences: true)
                    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                    .last ?? ""
                if !found.isEmpty, FileManager.default.isExecutableFile(atPath: found) {
                    return URL(fileURLWithPath: found)
                }
            }
        } catch {
            // ignore and continue
        }

        // 3) Fallback: ask the user's login shell (covers cases where PATH is set in shell startup files)
        do {
            let (stdout, _, status) = try runProcess(
                executableURL: URL(fileURLWithPath: "/bin/zsh"),
                arguments: ["-lc", "command -v obsidian"],
                environment: mergedGUIPathEnvironment()
            )
            if status == 0 {
                let found = stdout
                    .split(separator: "\n", omittingEmptySubsequences: true)
                    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                    .last ?? ""
                if !found.isEmpty, FileManager.default.isExecutableFile(atPath: found) {
                    return URL(fileURLWithPath: found)
                }
            }
        } catch {
            // ignore and continue
        }

        throw ExportError.obsidianNotFound
    }

    private static func mergedGUIPathEnvironment() -> [String: String] {
        // GUI apps often start with a minimal PATH. Extend with common locations.
        var env = ProcessInfo.processInfo.environment
        let existingPath = env["PATH"] ?? ""
        let extras = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]
        let merged = (extras + [existingPath])
            .filter { !$0.isEmpty }
            .joined(separator: ":")
        env["PATH"] = merged
        return env
    }

    private static func runProcess(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]
    ) throws -> (stdout: String, stderr: String, status: Int32) {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw ExportError.failedToLaunch(error.localizedDescription)
        }

        process.waitUntilExit()

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (stdout, stderr, process.terminationStatus)
    }

    /// The Obsidian CLI expects `\n` and `\t` escape sequences in content values.
    static func encodeContentValue(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\t", with: "\\t")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}

enum MarkdownDailyNoteInserter {
    static func insert(note: String, into document: String, underHeader header: String) -> String {
        let trimmedHeader = header.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDoc = document

        // If no header configured, prepend at the top.
        if trimmedHeader.isEmpty {
            return prepend(note: note, to: normalizedDoc)
        }

        let lines = normalizedDoc.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let matcher = HeaderMatcher.make(from: trimmedHeader)

        if let headerIndex = lines.firstIndex(where: { matcher.matches($0) }) {
            var out = lines
            let headerLevel = HeaderMatcher.headerLevel(fromLine: out[headerIndex])

            // Find the end of this section: next header with level <= current.
            let endIndex = out[(headerIndex + 1)...].firstIndex(where: {
                HeaderMatcher.isHeaderLine($0, maxLevel: headerLevel)
            }) ?? out.count

            var insertIndex = endIndex

            // If the section already ends with blank lines, insert before them.
            while insertIndex > (headerIndex + 1), out[insertIndex - 1].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                insertIndex -= 1
            }

            var block = note.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

            // Ensure separation from previous content inside the section.
            if insertIndex > (headerIndex + 1), !out[insertIndex - 1].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                block.insert("", at: 0)
            }

            // Ensure a blank line before the next header (if any).
            if endIndex < out.count {
                if let last = block.last, !last.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    block.append("")
                }
            }

            out.insert(contentsOf: block, at: insertIndex)
            return out.joined(separator: "\n")
        }

        // Header not found: append it at the end, then the note.
        let headerLine = HeaderMatcher.renderHeaderLine(from: trimmedHeader)
        var outDoc = normalizedDoc
        if !outDoc.hasSuffix("\n") { outDoc += "\n" }
        if !outDoc.hasSuffix("\n\n") { outDoc += "\n" }
        outDoc += headerLine + "\n" + note + "\n"
        return outDoc
    }

    private static func prepend(note: String, to document: String) -> String {
        if document.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return note + "\n"
        }
        return note + "\n\n" + document
    }

    private struct HeaderMatcher {
        let matches: (String) -> Bool

        static func make(from configured: String) -> HeaderMatcher {
            let c = configured.trimmingCharacters(in: .whitespacesAndNewlines)
            if c.hasPrefix("#") {
                return HeaderMatcher { line in
                    line.trimmingCharacters(in: .whitespacesAndNewlines) == c
                }
            }

            return HeaderMatcher { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.hasPrefix("#") else { return false }
                let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                guard parts.count == 2 else { return false }
                return String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines) == c
            }
        }

        static func renderHeaderLine(from configured: String) -> String {
            let c = configured.trimmingCharacters(in: .whitespacesAndNewlines)
            if c.hasPrefix("#") { return c }
            return "# " + c
        }

        static func headerLevel(fromLine line: String) -> Int {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let count = trimmed.prefix(while: { $0 == "#" }).count
            return max(1, min(6, count == 0 ? 2 : count))
        }

        static func isHeaderLine(_ line: String, maxLevel: Int) -> Bool {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("#") else { return false }
            let level = trimmed.prefix(while: { $0 == "#" }).count
            guard level >= 1 && level <= 6 else { return false }
            // Treat any header of same-or-higher rank (<= level number) as a boundary.
            return level <= maxLevel
        }
    }
}
