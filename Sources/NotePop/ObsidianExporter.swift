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
            return "Could not find the `obsidian` CLI. (NotePop normally exports without launching Obsidian; this error only applies if CLI fallback is used.)"
        case .failedToLaunch(let message):
            return "Failed to run helper process: \(message)"
        case .nonZeroExit(let code, let stderr):
            if stderr.isEmpty {
                return "Obsidian CLI exited with code \(code)."
            }
            return "Obsidian CLI exited with code \(code): \(stderr)"
        case .invalidDailyPath(let value):
            return "Could not determine the daily note path: \(value)"
        case .invalidVaultPath(let value):
            return "Could not determine the Obsidian vault path: \(value)"
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
            // Avoid launching Obsidian (which can create transient Dock icons) by writing directly
            // to the daily note file based on Obsidian's local config.
            let dailyURL = try ObsidianLocalDailyNoteLocator.todaysDailyNoteURL()

            let current: String
            if let data = try? Data(contentsOf: dailyURL), let str = String(data: data, encoding: .utf8) {
                current = str.replacingOccurrences(of: "\r\n", with: "\n")
            } else {
                current = ""
            }

            let updated = MarkdownDailyNoteInserter.insert(note: trimmedNote, into: current, underHeader: dailyHeader)

            let dirURL = dailyURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
            try Data(updated.utf8).write(to: dailyURL, options: .atomic)
        }.value
    }
}

enum ObsidianLocalDailyNoteLocator {
    private struct VaultInfo {
        let id: String
        let path: String
    }

    private struct DailyNoteSettings {
        let folder: String
        let format: String
    }

    static func todaysDailyNoteURL(now: Date = Date()) throws -> URL {
        let vaultURL = try preferredVaultURL()
        let settings = readDailyNoteSettings(vaultURL: vaultURL)

        let filename = dailyFilename(for: now, momentFormat: settings.format)
        var relativePath = "\(filename).md"

        let trimmedFolder = settings.folder.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedFolder.isEmpty {
            let folderPath = trimmedFolder
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            relativePath = folderPath + "/" + relativePath
        }

        return vaultURL.appendingPathComponent(relativePath)
    }

    private static func preferredVaultURL() throws -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let obsidianConfigURL = home
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("obsidian")
            .appendingPathComponent("obsidian.json")

        guard let data = try? Data(contentsOf: obsidianConfigURL) else {
            throw ExportError.invalidVaultPath("Missing Obsidian config at: \(obsidianConfigURL.path)")
        }

        let jsonAny = try JSONSerialization.jsonObject(with: data)
        guard let json = jsonAny as? [String: Any] else {
            throw ExportError.invalidVaultPath("Invalid Obsidian config JSON")
        }

        let preferredID = (json["activeVault"] as? String)
            ?? (json["lastActiveVault"] as? String)
            ?? (json["lastOpenVault"] as? String)
            ?? (json["lastVaultId"] as? String)

        let vaultsAny = json["vaults"]
        guard let vaultsDict = vaultsAny as? [String: Any] else {
            throw ExportError.invalidVaultPath("Obsidian config missing 'vaults'")
        }

        var vaults: [VaultInfo] = []
        vaults.reserveCapacity(vaultsDict.count)
        for (id, value) in vaultsDict {
            guard let info = value as? [String: Any] else { continue }
            if let path = info["path"] as? String, !path.isEmpty {
                vaults.append(VaultInfo(id: id, path: path))
            }
        }

        if let preferredID, let match = vaults.first(where: { $0.id == preferredID }) {
            return URL(fileURLWithPath: match.path)
        }

        // If we can't determine a preferred vault, fall back to a stable choice.
        if let only = vaults.first, vaults.count == 1 {
            return URL(fileURLWithPath: only.path)
        }
        if let firstStable = vaults.sorted(by: { $0.id < $1.id }).first {
            return URL(fileURLWithPath: firstStable.path)
        }

        throw ExportError.invalidVaultPath("No vault paths found in Obsidian config")
    }

    private static func readDailyNoteSettings(vaultURL: URL) -> DailyNoteSettings {
        let settingsURL = vaultURL
            .appendingPathComponent(".obsidian")
            .appendingPathComponent("daily-notes.json")

        guard let data = try? Data(contentsOf: settingsURL),
              let jsonAny = try? JSONSerialization.jsonObject(with: data),
              let json = jsonAny as? [String: Any]
        else {
            return DailyNoteSettings(folder: "", format: "YYYY-MM-DD")
        }

        let folder = (json["folder"] as? String) ?? ""
        let format = (json["format"] as? String) ?? "YYYY-MM-DD"
        return DailyNoteSettings(folder: folder, format: format)
    }

    private static func dailyFilename(for date: Date, momentFormat: String) -> String {
        let fmt = momentFormat.trimmingCharacters(in: .whitespacesAndNewlines)
        let dateFormat = momentToICUDateFormat(fmt)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = dateFormat
        return formatter.string(from: date)
    }

    private static func momentToICUDateFormat(_ moment: String) -> String {
        // Minimal Moment.js -> ICU mapping for common Obsidian daily note formats.
        // If we can't map it cleanly, fall back to a safe default.
        if moment.isEmpty { return "yyyy-MM-dd" }

        var s = moment
        // Moment literals are written like [text]
        s = s.replacingOccurrences(of: "[", with: "")
        s = s.replacingOccurrences(of: "]", with: "")

        // Replace longer tokens first.
        let replacements: [(String, String)] = [
            ("YYYY", "yyyy"),
            ("YY", "yy"),
            ("MMMM", "MMMM"),
            ("MMM", "MMM"),
            ("MM", "MM"),
            ("DD", "dd"),
            ("D", "d"),
            ("dddd", "EEEE"),
            ("ddd", "EEE"),
            ("HH", "HH"),
            ("H", "H"),
            ("mm", "mm")
        ]
        for (from, to) in replacements {
            s = s.replacingOccurrences(of: from, with: to)
        }

        // If there are still obvious Moment tokens left, use a default.
        if s.range(of: "[A-Za-z]", options: .regularExpression) != nil {
            // Allow ICU letters; but if the original had tokens we didn't replace, this is risky.
            // Heuristic: if it still contains common Moment tokens, fall back.
            let suspicious = ["Do", "Qo", "X", "x", "ww", "Wo"]
            if suspicious.contains(where: { moment.contains($0) }) {
                return "yyyy-MM-dd"
            }
        }

        return s
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
